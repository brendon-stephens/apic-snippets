exports.setCachePolicy = ({
    urlPattern, // shell-style match pattern that identifies the match document
    ttl = 900, // validity period in seconds to cache the document
    priority = 128, // priority of a document to add to or remove from the cache
    cacheBackendResponse= true, // caches the response to a GET request
    cachePostPutResponse = false, // caches the response for POST and PUT requests
    httpCacheValidation = false, // honour the http cache headers from the client
    returnExpiredDocument = false, // return expired document in the case of a connection error
    restfulInvalidation = false // invalidate the document when a PUT, POST, or DELETE request matches the entry
}) => {
    const apim = require('apim')
    const sm = require('service-metadata')

    const cachePolicies = apim.getvariable('context.cachePolicies') ?? []
    
    cachePolicies.push({
        urlPattern,
        ttl,
        priority,
        cacheBackendResponse,
        cachePostPutResponse,
        httpCacheValidation,
        returnExpiredDocument,
        restfulInvalidation
    })

    apim.setvariable('context.cachePolicies', cachePolicies)

    // create the policy xml as defined in store:/schemas/caching-policies.xsd
    const policyXml = `
    <dcp:caching-policies xmlns:dcp="http://www.datapower.com/schemas/caching">${cachePolicies.map(item => `
        <dcp:caching-policy url-match="${item.urlPattern}" priority="${item.priority}">
            <dcp:fixed ttl="${item.ttl}"
                cache-post-put-response="${item.cachePostPutResponse}" 
                cache-backend-response="${item.cacheBackendResponse}" 
                http-cache-validation="${item.httpCacheValidation}" 
                return-expired-document="${item.returnExpiredDocument}" 
                restful-invalidation="${item.restfulInvalidation}" 
            />
        </dcp:caching-policy>`)}
    </dcp:caching-policies>`

    console.debug(`Updated caching policies:\n${policyXml}`)

    sm.setVar('var://service/cache/dynamic-policies', policyXml) 
}

exports.promisify = (fn) => {
    return (...args) => new Promise((resolve, reject) => {
      fn(...args, (error, result) => {
        if (error) {
          reject(error instanceof Error ? error : Error(String(error)))
        }
        resolve(result)
      })
    })
}

exports.promisifyChild = (parent, child) => {
    return (...args) => new Promise((resolve, reject) => {
      child.call(parent, ...args, (error, result) => {
        if (error) {
          reject(error instanceof Error ? error : Error(String(error)))
        }
        resolve(result)
      })
    })
}
