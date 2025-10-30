<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:dpgui="http://www.datapower.com/extensions/webgui"
    xmlns:dpe="http://www.datapower.com/extensions"
    xmlns:dp="http://www.datapower.com/schemas/management"
    xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:func="http://exslt.org/functions"
    extension-element-prefixes="dpe dpgui func"
    exclude-result-prefixes="dpgui dpe dp env func">
    <!-- *******************************************************************
    ** @template map-au-custom.xsl
    ** @desc     Custom authentication to be used as part of the RBM
    **           flow. This code flips the standard behaviour of Datapower
    **           by attempting to authenticate the user against local user
    **           registry before attempting to query LDAP. This is intended
    **           to reduce queries sent to LDAP servers.
    ** @author   Brendon Stephens
    ** @created  September 2025
    ******************************************************************** -->
    <!-- Output config -->
    <xsl:output method="xml" encoding="utf-8" indent="yes"/>
    <!-- Global stylesheet variables -->
    <xsl:variable name="DEBUG" select="dpe:variable('var://system/map/debug')"/>
    <xsl:variable name="RBM" select="dpe:variable('var://system/rbm/config')"/>
    <xsl:variable name="RBM_CONFIG" select="dpe:parse($RBM)/RBMSettings"/>
    <xsl:variable name="FALLBACK_MODE" select="normalize-space($RBM_CONFIG/FallbackLogin)"/>
    <xsl:variable name="LDAP_PARAMS" select="dpe:get-ldap-search-parameters($RBM_CONFIG/AULDAPSearchParameters)" />
    <xsl:variable name="LDAP_HOST" select="$RBM_CONFIG/AUHost"/>
    <xsl:variable name="LDAP_PORT" select="$RBM_CONFIG/AUPort"/>
    <xsl:variable name="LDAP_SERVER" select="concat($LDAP_HOST, ':', $LDAP_PORT)"/>
    <xsl:variable name="LDAP_BIND_PREFIX" select="$LDAP_PARAMS/LDAPSearchParameters/LDAPFilterPrefix"/>
    <xsl:variable name="LDAP_BIND_SUFFIX" select="$LDAP_PARAMS/LDAPSearchParameters/LDAPFilterSuffix"/>
    <xsl:variable name="LDAP_TIMEOUT" select="$RBM_CONFIG/AULDAPReadTimeout"/>
    <xsl:variable name="LDAP_VERSION" select="$RBM_CONFIG/LDAPVersion"/>
    <xsl:variable name="LDAP_CLIENT_PROFILE">
        <xsl:choose>
            <xsl:when test="$RBM_CONFIG/LDAPSSLClientConfigType = 'client' and normalize-space($RBM_CONFIG/LDAPSSLClientProfile)">
                <xsl:value-of select="concat('client:', $RBM_CONFIG/LDAPSSLClientProfile)"/>
            </xsl:when>
            <xsl:when test="$RBM_CONFIG/AULDAPSSLClientConfigType = 'proxy' and normalize-space($RBM_CONFIG/AULDAPSSLProxyProfile)">
                <xsl:value-of select="$RBM_CONFIG/AULDAPSSLProxyProfile"/>
            </xsl:when>
        </xsl:choose>
    </xsl:variable>
    <xsl:variable name="LDAP_LB_GROUP" select="$RBM_CONFIG/AULDAPLoadBalanceGroup"/>
    <xsl:variable name="USERNAME" select="normalize-space(/identity/entry/username)"/>
    <xsl:variable name="PASSWORD" select="normalize-space(/identity/entry/password)"/>
    <xsl:variable name="CLIENT_IP" select="normalize-space(/identity/entry/client-ip-address)"/>
    <xsl:variable name="LOGIN_TYPE" select="normalize-space(/identity/entry/login-type)"/>
    <!-- Root template -->
    <xsl:template match="/">
        <xsl:if test="($DEBUG &gt; 2)">
            <xsl:message dpe:type="rbm" dpe:priority="debug" dpe:class="rbm" dpe:object="RBM-Settings">
                <xsl:text>rbm-config: </xsl:text>
                <xsl:copy-of select="$RBM_CONFIG"/>
            </xsl:message>
            <xsl:message dpe:type="rbm" dpe:priority="debug" dpe:class="rbm" dpe:object="RBM-Settings">
                <xsl:text>ldap-search-params: </xsl:text>
                <xsl:copy-of select="$LDAP_PARAMS"/>
            </xsl:message>
        </xsl:if>
        <xsl:choose>
            <!-- First, check that fallback mode (local user auth) is enabled -->
            <xsl:when test="$FALLBACK_MODE = 'local' or ($FALLBACK_MODE = 'restricted' and $RBM_CONFIG/FallbackUser[. = $USERNAME])">
                <xsl:choose>
                    <!-- Okay it's enabled, now check if the user is defined locally -->
                    <xsl:when test="dpgui:get-config('default', 'User', $USERNAME, 0)/configuration/User">
                        <xsl:if test="($DEBUG &gt; 2)">
                            <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings">
                                <xsl:value-of select="concat('User ', $USERNAME, ' exists locally. Attempting local authentication.')"/>
                            </xsl:message>
                        </xsl:if>
                        <!-- The user account is defined locally, let's try authenticate -->
                        <xsl:variable name="LOCAL_AUTH_RESULT">
                            <xsl:copy-of select="dpgui:authenticate-user($USERNAME, $PASSWORD, $CLIENT_IP, $LOGIN_TYPE)"/>
                            <!-- Prevent native fallback functionality post-failure of ldap call -->
                            <dpe:set-variable name="'var://context/RBM/try-fallback'" value="'0'"/>
                        </xsl:variable>
                        <xsl:choose>
                            <!-- If there is a string result, it indicates the user authenticated successfully -->
                            <xsl:when test="normalize-space($LOCAL_AUTH_RESULT) != ''">
                                <xsl:if test="($DEBUG &gt; 2)">
                                    <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings">
                                        <xsl:value-of select="concat('Authenticated user ', $USERNAME, ' to local user account. Skipping ldap check.')"/>
                                    </xsl:message>
                                </xsl:if>
                                <credentials>
                                    <entry type="local">
                                        <xsl:value-of select="$USERNAME"/>
                                    </entry>
                                </credentials>
                            </xsl:when>
                            <xsl:otherwise>
                                <!-- The result string is empty meaning the local auth failed -->
                                <xsl:if test="($DEBUG &gt; 2)">
                                    <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings">
                                        <xsl:value-of select="concat('Could not authenticate user ', $USERNAME, ' to local user account')"/>
                                    </xsl:message>
                                </xsl:if>
                                <dpe:reject/>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:when>
                    <xsl:otherwise>
                        <!-- Even though fallback mode is enabled, the local user account doesn't exist, so don't try to authenticate locally -->
                        <xsl:if test="($DEBUG &gt; 2)">
                            <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings">
                                <xsl:value-of select="concat('User ', $USERNAME, ' does not exist locally. Will attempt ldap authentication.')"/>
                            </xsl:message>
                        </xsl:if>
                        <!-- Try to authenticate against ldap -->
                        <xsl:call-template name="ldap-authenticate"/>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:when>
            <xsl:otherwise>
                <!-- Fallback mode is disabled or not relevant for this user -->
                <xsl:if test="($DEBUG &gt; 2)">
                    <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings">
                        <xsl:value-of select="concat('Fallback mode disabled or not configured for user ', $USERNAME, '. Will attempt ldap authentication.')"/>
                    </xsl:message>
                </xsl:if>
                <!-- Try to authenticate against ldap -->
                <xsl:call-template name="ldap-authenticate"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    <!-- Named template to authenticate the user against ldap -->
    <xsl:template name="ldap-authenticate">
        <!-- Query the LDAP server for Datapower roles assigned to the user -->
        <xsl:variable name="LDAP_BIND" select="concat($LDAP_BIND_PREFIX, $USERNAME, $LDAP_BIND_SUFFIX)"/>
        <xsl:variable name="LDAP_AUTH_RESULT" select="dpe:ldap-authen(
            $LDAP_BIND,
            $PASSWORD,
            $LDAP_SERVER,
            $LDAP_CLIENT_PROFILE,
            $LDAP_LB_GROUP,
            $LDAP_VERSION,
            $LDAP_TIMEOUT
        )"/>
        <xsl:if test="($DEBUG &gt; 2)">
            <xsl:message dpe:type="rbm" dpe:priority="debug" dpe:class="rbm" dpe:object="RBM-Settings">
                <xsl:text>ldap-authent result: </xsl:text>
                <xsl:copy-of select="$LDAP_AUTH_RESULT"/>
            </xsl:message>
        </xsl:if>
        <xsl:choose>
            <xsl:when test="normalize-space($LDAP_AUTH_RESULT)">
                <!-- Authentication successful -->
                <credentials>
                    <xsl:copy-of select="$LDAP_AUTH_RESULT"/>
                </credentials>
            </xsl:when>
            <xsl:otherwise>
                <!-- Authentication failed -->
                <dpe:reject/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
</xsl:stylesheet>
<!-- That's all folks -->
