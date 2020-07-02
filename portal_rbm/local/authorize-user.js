const jwt = require('jwt')
const urlopen = require('urlopen')
const transform = require('transform')
const hm = require('header-metadata');

// environment properties to be loaded via properties file
const PLATFORM_ENDPOINT = 'https://apic-platform-api.example.org/api'
const SSL_CLIENT_PROFILE = 'Proxy_ClientProfile_V1'
const LDAP_SERVER = 'ldap.example.org'
const LDAP_BIND_DN = 'CN=SVC_APICProd,OU=Service Accounts,OU=DEPT,DC=EXAMPLE,DC=ORG'
const LDAP_BIND_PASSWORD = 'password'
const LDAP_TARGET_DN = 'OU=TIM,OU=Groups,OU=DEPT,DC=EXAMPLE,DC=ORG'
const LDAP_ATTRIBUTE_NAME = 'member'
const LDAP_FILTER = '(&(member=*)(cn=GR-APIC_*))'
const APIC_ORG = 'admin'
const APIC_USERNAME = 'admin'
const APIC_PASSWORD = 'password'
const APIC_CLIENT_ID = 'datapowerdemo'
const APIC_CLIENT_SECRET = 'secret'
const APIC_USER_REALM = 'admin/default-idp-1'
const APIC_REGISTRY = 'sso-oidc'

// mapping between ldap groups and api connect roles
const ROLE_MAPPING = {
    'GR-APIC_ADMIN_MEMBER': 'administrator',
    'GR-APIC_ADMIN_VIEWER': 'viewer'
}

// parse the token response 
session.input.readAsJSON((error, response) => {
    if (error) {
        return rejectToErrorFlow({
            error: 'server_error', 
            error_description: 'The token proxy failed to parse the token response.'
        }, error)
    }

    if (hm.response.statusCode != 200) {
        // proxy error responses
        return session.output.write(response)
    }

    const id_token = response.id_token

    if (!id_token) {
        return rejectToErrorFlow({
            error: 'server_error', 
            error_description: 'The token proxy failed to find an id_token in the token response.'
        })
    }

    // decode the id token
    let decoder = jwt.Decoder(id_token)
    decoder.decode((error, claims) => {
        if (error) {
            return rejectToErrorFlow({
                error: 'server_error', 
                error_description: 'The token proxy failed to decode the id_token.'
            }, error)
        }

        if (!claims.sub) {
            return rejectToErrorFlow({
                error: 'server_error', 
                error_description: 'The token proxy failed to find a sub claim in the id_token.'
            })
        }

        processTokenUser(claims)

        // proxy the response back
        session.output.write(response)

    })
})

/**
 * The main processing flow for granting access to a user.
 * 
 * @param {object} id_token identity token returned from OAuth token service.
 */
function processTokenUser(id_token) {

    const username = id_token.sub

    let headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
    }

    // get an access token for the platform-api
    handleRequest('post', '/token', headers, {
        username: APIC_USERNAME,
        password: APIC_PASSWORD,
        client_id: APIC_CLIENT_ID,
        client_secret: APIC_CLIENT_SECRET,
        grant_type: 'password',
        realm: APIC_USER_REALM
    })
    .then((response) => {
        headers.Authorization = `Bearer ${response.access_token}`
        // get all current users from the oidc registry
        return handleRequest('get', `/user-registries/${APIC_ORG}/${APIC_REGISTRY}/users?fields=username,url`, headers)
    }).then((response) => {
        const user = response.results.find(x => username == x.username)

        if (!user) {
            // create the user in the oidc registry
            return handleRequest('post', `/user-registries/${APIC_ORG}/${APIC_REGISTRY}/users`, headers, {
                username: id_token.sub,
                first_name: id_token.given_name,
                last_name: id_token.family_name,
                email: id_token.email,
                identity_provider: APIC_REGISTRY
            })
        }
        // user already exists in the oidc registry
        return Promise.resolve(user)
    }).then(async (user) => {
        const username = user.username

        // retrieve ldap groups related to user
        let ldap_groups = []
        try {
            ldap_groups = await getLdapGroupUsers()
        } catch (error) {
            return Promise.reject(error)
        }

        // match the ldap groups to api connect roles
        let user_roles = []
        for (let key in ROLE_MAPPING) {
            let result = ldap_groups.find(x => x.dn == key)
            if (result) {
                result.members.includes(username.toUpperCase()) ? user_roles.push(ROLE_MAPPING[key]) : ''
            }
        }

        // retrieve the api connect organisation roles
        let org_roles = []
        try {
            const response = await handleRequest('get', `/orgs/${APIC_ORG}/roles?fields=name,title,url`, headers)
            org_roles = response.results
        } catch (error) {
            return Promise.reject(error)
        }

        // match the user roles with the api connect role urls
        let role_urls = []
        for (let i = 0; i < org_roles.length; i++) {
            let org_role = org_roles[i]
            user_roles.includes(org_role.name) ? role_urls.push(org_role.url) : ''
        }

        // retrieve a list of current organisation members
        let members = []
        try {
            const response = await handleRequest('get', `/orgs/${APIC_ORG}/members?fields=name,title,url`, headers)
            members = response.results
        } catch (error) {
            return Promise.reject(error)
        }

        // try and find if the member already exists
        const member = members.find(x => x.name == username && x.title == username)

        if (member) {
            // update the existing member record with roles
            return handleRequest('patch', `/orgs/${APIC_ORG}/members/${member.name}`, headers, {
                role_urls
            })
        } else {
            // create a new member record with roles
            return handleRequest('post', `/orgs/${APIC_ORG}/members`, headers, {
                user: {
                    url: user.url
                },
                role_urls
            })
        }
    }).then((member) => {
        console.debug('Created/Updated member', JSON.stringify(member))
    }).catch((error) => {
        console.error('Error provisioning access', JSON.stringify(error))
        // we wan't to prevent the token from being proxied back to api connect, as 
        // the member might already exist and potentially could have had their 
        // access changed. thus, we NEED to create/update a member record every 
        // time the user authenticates
        return rejectToErrorFlow({
            error: 'server_error', 
            error_description: 'The token proxy failed to provision access.'
        })
    })
}

/**
 * Common error handling routine to send back error messages in a consistent
 * format.
 * 
 * @param {string} error error category, should match OAuth2.0 framework RFC6749.
 * @param {string} error_description description descibing the error that occured.
 */
function rejectToErrorFlow(error, error_description) {
    console.error('Error provisioning access')

    session.output.write({
        error,
        error_description
    })
}

/**
 * Queries an LDAP server for a set of LDAP groups and their associated members,
 * based on the configured filter. The LDAP search is done via DataPower XSLT 
 * and the results are transformed via JSONX to JSON. 
 * 
 * @return {Promise} JSON document containing LDAP results.
 */
function getLdapGroupUsers() {
    return new Promise((resolve, reject) => {
        // TODO: Find a better query. Instead of getting all users for 
        // a group, we should get all groups for a user. 

        // use xslt processer to perform ldap-search functionality
        let options = {
            xmldom: XML.parse('<blank/>'),
            location: "local:///ldap-search.xsl",
            parameters: {
                'SERVER_ADDRESS': LDAP_SERVER,
                'BIND_DN': LDAP_BIND_DN,
                'BIND_PASSWORD': LDAP_BIND_PASSWORD,
                'TARGET_DN': LDAP_TARGET_DN,
                'ATTRIBUTE_NAME': LDAP_ATTRIBUTE_NAME,
                'FILTER': LDAP_FILTER,
                'SSL_PROXY_PROFILE': `client:${SSL_CLIENT_PROFILE}`
            }
        }

        transform.xslt(options, (error, result) => {
            if (error) {
                console.error('ldap-search transform error', JSON.stringify(error))
                return reject(error)
            }

            options = {
                xmldom: result,
                location: 'local:///ldap-result-to-json.xsl'
            }

            transform.xslt(options, (error, result) => {
                if (error) {
                    console.error('ldap-result-to-json transform error', JSON.stringify(error))
                    return reject(error)
                }

                // TODO: This seems a little dodgy... surely a better way.
                // parse the xml output (json string) as json object
                const json = JSON.parse(XML.stringify({omitXmlDeclaration: true}, result))
                return resolve(json.results)
            })
        })
    })
}

/**
 * Generic urlopen handler for API calls to the API Connect REST management 
 * interface. This function interacts with a given resource and handles errors
 * and responses in a consistent manner.
 * 
 * @param {string} method the HTTP method to invoke with
 * @param {string} resource the API Connect resource path
 * @param {object} headers headers map to send in the request
 * @param {object} data body data to send in the request
 */
function handleRequest(method, resource, headers, data) {
    const request = {
        target: `${PLATFORM_ENDPOINT}${resource}`,
        sslClientProfile: SSL_CLIENT_PROFILE,
        headers,
        method,
        ...data && { data: JSON.stringify(data) }
    }

    console.error(`handleRequest: ${method.toUpperCase()}:${resource}`)

    return new Promise((resolve, reject) => {
        urlopen.open(request, (error, response) => {
            if (error) {
                console.error(`urlopen error on resource: '${request.target}'`, JSON.stringify(error))
                return reject(error)
            }

            if (response.statusCode >= 300) {
                console.error(`non 2xx response from resource: '${request.target}'`)
                return reject(response)
            }

            response.readAsJSON((error, json) => {
                if (error) {
                    console.error(`parse error from resource response: '${request.target}'`, JSON.stringify(error))
                    return reject(error)
                }
                return resolve(json)
            })
        })
    })
}