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
    ** @template map-mc-login.xsl
    ** @desc     Custom map credentials script to be used post-login to
    **           query LDAP roles for the authenticated user. The script 
    **           will take the CN from the authenticated DN and use it for
    **           the lookup. The resulted LDAP roles are mapped to Datapower 
    **           access policies, as defined in "User Group" config objects.
    ** @author   Brendon Stephens
    ** @created  August 2025
    ******************************************************************** -->

    <xsl:include href="store:///dp/msgcat/crypto.xml.xsl"/>
    <xsl:include href="store:///dp/msgcat/xslt.xml.xsl"/>
    
    <xsl:output method="xml" encoding="utf-8" indent="yes"/>

    <!-- Grab the system variable for rbm debug logging -->
    <xsl:variable name="DEBUG" select="dpe:variable('var://system/map/debug')"/>

    <xsl:variable name="LC">abcdefghijklmnopqrstuvwxyz</xsl:variable>
    <xsl:variable name="UC">ABCDEFGHIJKLMNOPQRSTUVWXYZ</xsl:variable>

    <xsl:variable name="LDAP_HOST" select="example.org"/>
    <xsl:variable name="LDAP_PORT" select=""/>
    <xsl:variable name="LDAP_FILTER_PREFIX" select="'(&amp;(member=cn='"/>
    <xsl:variable name="LDAP_FILTER_SUFFIX" select="',ou=users,ou=staff,o=example,c=org)(objectClass=groupOfNames))'"/>
    <xsl:variable name="LDAP_BIND" select="'cn=datapower_rbm,ou=users,ou=system,o=example,c=org'"/>
    <xsl:variable name="LDAP_BIND_PASSWORD" select="'password123'"/> <!-- Can be prefixed with alias: -->
    <xsl:variable name="LDAP_BASE_DN" select="'ou=ibm_datapower_gateway,ou=roles,ou=staff,o=example,c=org'"/>
    <xsl:variable name="LDAP_TIMEOUT" select="'15'"/>
    <xsl:variable name="LDAP_VERSION" select="'v3'"/>
    <xsl:variable name="LDAP_RESULT_ATTRIBUTE" select="'cn'"/>
    <xsl:variable name="LDAP_RESULT_SCOPE" select="'sub'"/>
    <xsl:variable name="LDAP_CLIENT_PROFILE" select="''"/>
    <xsl:variable name="LDAP_LB_GROUP" select="''"/>

    <xsl:template match="/">
        <!-- Grab the CN of the user from the certificate DN -->
        <xsl:variable name="CREDENTIAL" select="substring-after(translate(string(/credentials/*[1]), $UC, $LC), 'cn=')"/>
        <!-- Build the LDAP filter string using the CN -->
        <xsl:variable name="LDAP_FILTER" select="concat($LDAP_FILTER_PREFIX, $CREDENTIAL, $LDAP_FILTER_SUFFIX)"/>
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
        <xsl:variable name="ENTRY" select="$SEARCH_RESULT/LDAP-search-results/result"/>
        <xsl:variable name="SEARCH_ERROR" select="$SEARCH_RESULT/LDAP-search-error/error"/>
        <xsl:choose>
            <xsl:when test="$SEARCH_ERROR != ''">
                <!-- Error with the LDAP bind etc. -->
                <xsl:message dpe:type="rbm" dpe:priority="error" dpe:class="rbm" dpe:object="RBM-Settings" dpe:id="{$DPLOG_XSLT_LDAP_RBMERROR}">
                    <dpe:with-param value="{$SEARCH_ERROR}"/>
                </xsl:message>
            </xsl:when>
            <xsl:when test="count($ENTRY) = 0">
                <!-- No results -->
                <xsl:if test="($DEBUG &gt; 2)">
                    <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings" dpe:id="{$DPLOG_XSLT_NOENTRYFOUND}">
                        <dpe:with-param value="{$filter}"/>
                    </xsl:message>
                </xsl:if>
            </xsl:when>
            <xsl:otherwise>
                <xsl:if test="($DEBUG &gt; 2)">
                    <xsl:if test="count($ENTRY) &gt; 1">
                        <!-- More than one result found -->
                        <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings" dpe:id="{$DPLOG_XSLT_MULTENTRYFOUND}">
                            <dpe:with-param value="{$FILTER}"/>
                        </xsl:message>
                    </xsl:if>
                </xsl:if>
                <!-- Lookup the access profiles for each role -->
                <xsl:for-each select="$ENTRY">
                    <xsl:if test="($DEBUG &gt; 2)">
                        <xsl:message dpe:type="rbm" dpe:priority="info" dpe:class="rbm" dpe:object="RBM-Settings">
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
                    <xsl:copy-of select="dpgui:get-user-access('', $ROLE)"/>
                </xsl:for-each>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
</xsl:stylesheet>
