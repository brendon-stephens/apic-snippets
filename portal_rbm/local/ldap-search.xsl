<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
    xmlns:dp="http://www.datapower.com/extensions"
    xmlns:IN="http://www.datapower.com/param/config"
    extension-element-prefixes="dp"
    exclude-result-prefixes="dp">
    <xsl:output method="xml" indent="yes"/>
    <xsl:param name="IN:SERVER_ADDRESS" select="''"/>
    <xsl:param name="IN:PORT_NUMBER" select="'636'"/>
    <xsl:param name="IN:BIND_DN" select="''"/>
    <xsl:param name="IN:BIND_PASSWORD" select="''"/>
    <xsl:param name="IN:TARGET_DN" select="''"/>
    <xsl:param name="IN:ATTRIBUTE_NAME" select="''"/>
    <xsl:param name="IN:FILTER" select="''"/>
    <xsl:param name="IN:SCOPE" select="'sub'"/>
    <xsl:param name="IN:SSL_PROXY_PROFILE" select="''"/>
    <xsl:template match="/">
        <xsl:copy-of select="dp:ldap-search(
            $IN:SERVER_ADDRESS, 
            $IN:PORT_NUMBER, 
            $IN:BIND_DN, 
            $IN:BIND_PASSWORD, 
            $IN:TARGET_DN, 
            $IN:ATTRIBUTE_NAME, 
            $IN:FILTER, 
            $IN:SCOPE, 
            $IN:SSL_PROXY_PROFILE
        )"/>
    </xsl:template>
</xsl:stylesheet>