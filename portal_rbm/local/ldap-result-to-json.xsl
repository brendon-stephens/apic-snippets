<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:json="http://www.ibm.com/xmlns/prod/2009/jsonx"
    xmlns:exslt="http://exslt.org/common" 
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
    xmlns:dp="http://www.datapower.com/extensions"
    extension-element-prefixes="dp exslt"
    exclude-result-prefixes="dp">
    <xsl:output method="text" omit-xml-declaration="yes" encoding="UTF-8"/>
    <xsl:template match="LDAP-search-results">
        <xsl:variable name="JSONX">
            <json:object>
                <json:array name="results">
                    <xsl:apply-templates select="result"/>
                </json:array>
            </json:object>
        </xsl:variable>
        <xsl:copy-of select="dp:transform('store:///jsonx2json.xsl', exslt:node-set($JSONX))"/>
    </xsl:template>
    <xsl:template match="result">
        <json:object>
            <json:string name="dn">
                <xsl:value-of select="substring-before(substring-after(DN, 'CN='), ',')"/>
            </json:string>
            <json:array name="members">
                <xsl:apply-templates select="attribute-value[@name='member']"/>
            </json:array>
        </json:object>
    </xsl:template>
    <xsl:template match="attribute-value">
        <json:string>
            <xsl:value-of select="substring-before(substring-after(., 'CN='), ',')"/>
        </json:string>
    </xsl:template>
</xsl:stylesheet>