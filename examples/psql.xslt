<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  version="1.0">

    <xsl:template match="decl">
        <xsl:for-each select="decl[@x-tag='struct']">
            <xsl:apply-templates />
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="decl[@x-tag='struct']">
        <table>
            <name><xsl:value-of select="@x-id" /></name>
            <columns>
                <xsl:apply-templates select="decl[@x-tag='struct.attribute']" />
            </columns>
        </table>
    </xsl:template>

    <xsl:template match="decl[@x-tag='struct.attribute']">
        <xsl:variable name="name" select="@x-name" />
        <xsl:variable name="datatype" select="substring-after(@x-proxy,'.')" />
        <column name="{$name}">
            <datatype><xsl:value-of select="$datatype" /></datatype>
            <name><xsl:value-of select="@x-name" /></name>
            <xsl:if test="@x-default_value">
                <default_value><xsl:value-of select="@x-default_value" /></default_value>
            </xsl:if>
            <xsl:if test="@x-optional_p='true'">
                <min_occ>0</min_occ>
            </xsl:if>
            <xsl:if test="not(@x-optional_p) or @x-optional_p='false'">
                <min_occ>1</min_occ>
            </xsl:if>
            <xsl:if test="@x-container='multiple'">
                <max_occ>*</max_occ>
            </xsl:if>
            <xsl:if test="not(@x-container)">
                <max_occ>1</max_occ>
            </xsl:if>
        </column>
    </xsl:template>

    <xsl:template match="/nest/inst">
        <xsl:variable name="table" select="@x-tag" />
        <data>
            <table><xsl:value-of select='$table' /></table>
            <columns>
                <xsl:apply-templates select="child::inst" />
            </columns>
        </data>
    </xsl:template>

    <xsl:template match="child::inst">
        <column>
            <name><xsl:value-of select="substring-after(@x-name,'.')" /></name>
            <xsl:if test="@x-tag = 'struct.attribute'">
                <value><xsl:value-of select="text()" /></value>
            </xsl:if>
            <xsl:if test="@x-tag != 'struct.attribute'">
                <type><xsl:value-of select="@x-tag" /></type>
                <xsl:for-each select="child::inst">
                    <subcolumn>
                        <name><xsl:value-of select="substring-after(@x-name,'.')" /></name>
                        <value><xsl:value-of select="text()" /></value>
                        <datatype><xsl:value-of select="substring-after(@x-proxy,'.')" /></datatype>
                    </subcolumn>
                </xsl:for-each>
            </xsl:if>
        </column>
    </xsl:template>

</xsl:stylesheet>

