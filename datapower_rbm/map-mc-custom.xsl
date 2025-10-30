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
    ** @template map-mc-custom.xsl
    ** @desc     Custom map credentials to be used as part of RBM flow.
    **           This code will use the output from the custom authentication
    **           transform to determine the account type (local or ldap) and
    **           and query appropriate access roles.
    ** @author   Brendon Stephens
    ** @created  September 2025
    ******************************************************************** -->
    <!-- Included stylesheets -->
    <xsl:include href="store:///dp/msgcat/crypto.xml.xsl"/>
    <xsl:include href="store:///dp/msgcat/xslt.xml.xsl"/>
    <!-- Output config -->
    <xsl:output method="xml" encoding="utf-8" indent="yes"/>
    <!-- Global stylesheet variables -->
    <xsl:variable name="LC">abcdefghijklmnopqrstuvwxyz</xsl:variable>
    <xsl:variable name="UC">ABCDEFGHIJKLMNOPQRSTUVWXYZ</xsl:variable>
    <xsl:variable name="DEBUG" select="dpe:variable('var://system/map/debug')"/>
    <xsl:variable name="RBM" select="dpe:variable('var://system/rbm/config')"/>
    <xsl:variable name="RBM_CONFIG" select="dpe:parse($RBM)/RBMSettings"/>
    <xsl:variable name="FALLBACK_MODE" select="$RBM_CONFIG/FallbackLogin"/>
    <xsl:variable name="LDAP_PARAMS" select="dpe:get-ldap-search-parameters($RBM_CONFIG/MCLDAPSearchParameters)" />
    <xsl:variable name="LDAP_HOST" select="$RBM_CONFIG/MCHost"/>
    <xsl:variable name="LDAP_PORT" select="$RBM_CONFIG/MCPort"/>
    <xsl:variable name="LDAP_FILTER_PREFIX" select="$LDAP_PARAMS/LDAPSearchParameters/LDAPFilterPrefix"/>
    <xsl:variable name="LDAP_FILTER_SUFFIX" select="$LDAP_PARAMS/LDAPSearchParameters/LDAPFilterSuffix"/>
    <xsl:variable name="LDAP_BIND" select="$RBM_CONFIG/MCLDAPBindDN"/>
    <xsl:variable name="LDAP_BIND_PASSWORD">
        <xsl:choose>
            <!-- Preference hard password, as v10.0.5.8 firmware does not support password alias -->
            <xsl:when test="function-available('dpe:aaa-get-effective-password')">
                <xsl:value-of select="dpe:aaa-get-effective-password('default', $RBM_CONFIG/MCLDAPBindPasswordAlias)" />
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="concat('alias:', $RBM_CONFIG/MCLDAPBindPasswordAlias)" />
            </xsl:otherwise>
        </xsl:choose>
    </xsl:variable>
    <xsl:variable name="LDAP_BASE_DN" select="$LDAP_PARAMS/LDAPSearchParameters/LDAPBaseDN"/>
    <xsl:variable name="LDAP_TIMEOUT" select="$RBM_CONFIG/MCLDAPReadTimeout"/>
    <xsl:variable name="LDAP_VERSION" select="$RBM_CONFIG/LDAPVersion"/>
    <xsl:variable name="LDAP_RESULT_ATTRIBUTE" select="$LDAP_PARAMS/LDAPSearchParameters/LDAPReturnedAttribute"/>
    <xsl:variable name="LDAP_RESULT_SCOPE" select="'sub'"/>
    <xsl:variable name="LDAP_CLIENT_PROFILE">
        <xsl:choose>
            <xsl:when test="$RBM_CONFIG/MCLDAPSSLClientConfigType = 'client' and normalize-space($RBM_CONFIG/MCLDAPSSLClientProfile)">
                <xsl:value-of select="concat('client:', $RBM_CONFIG/MCLDAPSSLClientProfile)"/>
            </xsl:when>
            <xsl:when test="$RBM_CONFIG/MCLDAPSSLClientConfigType = 'proxy' and normalize-space($RBM_CONFIG/MCLDAPSSLProxyProfile)">
                <xsl:value-of select="$RBM_CONFIG/MCLDAPSSLProxyProfile"/>
            </xsl:when>
        </xsl:choose>
    </xsl:variable>
    <xsl:variable name="LDAP_LB_GROUP" select="$RBM_CONFIG/MCLDAPLoadBalanceGroup"/>
    <xsl:variable name="ENTRY_TYPE" select="normalize-space(/credentials/entry/credentials/entry/@type)"/>
    <xsl:variable name="ENTRY_VALUE" select="normalize-space(/credentials/entry/credentials/entry)"/>
    <!-- Root template -->
    <xsl:template match="/">
        <xsl:if test="($DEBUG &gt; 2)">
            <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings">
                <xsl:text>rbm-mc input: </xsl:text>
                <xsl:copy-of select="."/>
            </xsl:message>
            <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings">
                <xsl:text>ldap-search-params: </xsl:text>
                <xsl:copy-of select="$LDAP_PARAMS"/>
            </xsl:message>
        </xsl:if>
        <xsl:choose>
            <xsl:when test="$ENTRY_VALUE = ''">
                <!-- Shouldn't reach this, but silently fail if it does -->
            </xsl:when>
            <xsl:when test="$ENTRY_TYPE = 'local'">
                <!-- Get the access profiles for the user (via user group) -->
                <xsl:copy-of select="dpgui:get-user-access($ENTRY_VALUE)"/>
            </xsl:when>
            <xsl:when test="$ENTRY_TYPE = 'ldap'">
                <!-- Build the LDAP filter string using the cn -->
                <xsl:variable name="LDAP_FILTER" select="concat($LDAP_FILTER_PREFIX, $ENTRY_VALUE, $LDAP_FILTER_SUFFIX)"/>
                <!-- Query the LDAP server for Datapower roles assigned to the user -->
                <xsl:variable name="SEARCH_RESULT" select="dpe:ldap-search(
                    $LDAP_HOST,
                    $LDAP_PORT,
                    $LDAP_BIND,
                    $LDAP_BIND_PASSWORD,
                    $LDAP_BASE_DN,
                    $LDAP_RESULT_ATTRIBUTE,
                    $LDAP_FILTER,
                    $LDAP_RESULT_SCOPE,
                    $LDAP_CLIENT_PROFILE,
                    $LDAP_LB_GROUP,
                    $LDAP_VERSION,
                    $LDAP_TIMEOUT
                )"/>
                <!-- Parse the LDAP response -->
                <xsl:variable name="LDAP_RESULT" select="$SEARCH_RESULT/LDAP-search-results/result"/>
                <xsl:variable name="SEARCH_ERROR" select="$SEARCH_RESULT/LDAP-search-error/error"/>
                <xsl:choose>
                    <xsl:when test="$SEARCH_ERROR != ''">
                        <!-- Error with the LDAP bind etc. -->
                        <xsl:message dpe:type="rbm" dpe:priority="error" dpe:class="rbm" dpe:object="RBM-Settings" dpe:id="{$DPLOG_XSLT_LDAP_RBMERROR}">
                            <dpe:with-param value="{$SEARCH_ERROR}"/>
                        </xsl:message>
                    </xsl:when>
                    <xsl:when test="count($LDAP_RESULT) = 0">
                        <!-- No results -->
                        <xsl:if test="($DEBUG &gt; 2)">
                            <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings" dpe:id="{$DPLOG_XSLT_NOENTRYFOUND}">
                                <dpe:with-param value="{$LDAP_FILTER}"/>
                            </xsl:message>
                        </xsl:if>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:if test="($DEBUG &gt; 2)">
                            <xsl:if test="count($LDAP_RESULT) &gt; 1">
                                <!-- More than one result found -->
                                <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings" dpe:id="{$DPLOG_XSLT_MULTENTRYFOUND}">
                                    <dpe:with-param value="{$LDAP_FILTER}"/>
                                </xsl:message>
                            </xsl:if>
                        </xsl:if>
                        <!-- Lookup the access profiles for each role -->
                        <xsl:for-each select="$LDAP_RESULT">
                            <xsl:if test="($DEBUG &gt; 2)">
                                <xsl:message dpe:type="rbm" dpe:priority="debug" dpe:class="rbm" dpe:object="RBM-Settings">
                                    <xsl:text>Processing result: </xsl:text>
                                    <xsl:copy-of select="."/>
                                </xsl:message>
                            </xsl:if>
                            <xsl:variable name="ROLE" select="string(attribute-value[@name = $LDAP_RESULT_ATTRIBUTE])"/>
                            <xsl:if test="($DEBUG &gt; 2)">
                                <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings">
                                    <xsl:value-of select="concat('Matched user to role: ', $ROLE)"/>
                                </xsl:message>
                            </xsl:if>
                            <!-- Lookup the access profile for the user group -->
                            <xsl:copy-of select="dpgui:get-user-access('', $ROLE)"/>
                        </xsl:for-each>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:when>
            <xsl:otherwise>
                <!-- Unexpected at this stage, may have future support (eg. certificate) -->
                <xsl:message dpe:type="rbm" dpe:priority="error" dpe:class="rbm" dpe:object="RBM-Settings">
                    <xsl:value-of select="concat('Unsupported credential type (', $ENTRY_TYPE, ') input to custom credential mapping')"/>
                </xsl:message>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
</xsl:stylesheet>
<!-- That's all folks -->
