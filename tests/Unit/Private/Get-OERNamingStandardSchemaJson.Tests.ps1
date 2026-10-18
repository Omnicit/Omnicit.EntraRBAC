BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERNamingStandardSchemaJson' {
    It 'returns a string that parses as a draft-07 JSON Schema with the standard title' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERNamingStandardSchemaJson
            $Schema | Should -BeOfType ([string])
            $Obj = $Schema | ConvertFrom-Json
            $Obj.'$schema' | Should -Be 'http://json-schema.org/draft-07/schema#'
            $Obj.title | Should -Be 'Omnicit.EntraRBAC naming standard'
            $Obj.type | Should -Be 'object'
        }
    }

    It 'contains only ASCII characters' {
        InModuleScope $script:moduleName {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-OERNamingStandardSchemaJson))
            ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }

    It 'requires exactly version, separator, sections and segments at the root' {
        InModuleScope $script:moduleName {
            $Obj = Get-OERNamingStandardSchemaJson | ConvertFrom-Json
            @($Obj.required) | Should -Be @('version', 'separator', 'sections', 'segments')
        }
    }

    It 'forbids unknown keys at the root and in a segment' {
        InModuleScope $script:moduleName {
            $Obj = Get-OERNamingStandardSchemaJson | ConvertFrom-Json
            $Obj.additionalProperties | Should -BeFalse
            $Obj.properties.segments.items.additionalProperties | Should -BeFalse
        }
    }

    It 'requires only name in a segment, and refuses values together with pattern' {
        InModuleScope $script:moduleName {
            $Segment = (Get-OERNamingStandardSchemaJson | ConvertFrom-Json).properties.segments.items
            @($Segment.required) | Should -Be @('name')
            @($Segment.not.required) | Should -Be @('values', 'pattern')
        }
    }

    It 'lists the six sections in the documented order' {
        InModuleScope $script:moduleName {
            $Obj = Get-OERNamingStandardSchemaJson | ConvertFrom-Json
            @($Obj.properties.sections.items.enum) | Should -Be @(
                'groups', 'administrativeUnits', 'catalogs', 'accessPackages', 'assignmentPolicies', 'accessReviews')
            $Obj.properties.sections.minItems | Should -Be 1
            $Obj.properties.sections.uniqueItems | Should -BeTrue
        }
    }

    It 'lists the four letter cases in the documented order' {
        InModuleScope $script:moduleName {
            $Segment = (Get-OERNamingStandardSchemaJson | ConvertFrom-Json).properties.segments.items
            @($Segment.properties.case.enum) | Should -Be @('PascalCase', 'camelCase', 'UPPERCASE', 'lowercase')
        }
    }

    It 'pins version to 1.0 and bounds maxLength to 1-256' {
        InModuleScope $script:moduleName {
            $Props = (Get-OERNamingStandardSchemaJson | ConvertFrom-Json).properties
            @($Props.version.enum) | Should -Be @('1.0')
            $Props.maxLength.type | Should -Be 'integer'
            $Props.maxLength.minimum | Should -Be 1
            $Props.maxLength.maximum | Should -Be 256
            $Props.includeSyncedGroups.type | Should -Be 'boolean'
            $Props.includeSyncedGroups.default | Should -BeFalse
        }
    }

    It 'states the matching semantics in the description of pattern, exceptions, values and case' {
        InModuleScope $script:moduleName {
            $Obj = Get-OERNamingStandardSchemaJson | ConvertFrom-Json
            $Segment = $Obj.properties.segments.items.properties
            $Segment.pattern.description | Should -Match 'anchored at both ends'
            $Segment.pattern.description | Should -Match '\(\?i\)'
            $Obj.properties.exceptions.description | Should -Match 'anchored at both ends'
            $Obj.properties.exceptions.description | Should -Match '\(\?i\)'
            $Segment.values.description | Should -Match 'case-sensitive'
            $Segment.case.description | Should -Match 'PascalCase'
            $Segment.case.description | Should -Match 'UPPERCASE'
        }
    }

    It 'accepts the example standard and refuses an unknown root key (draft-07)' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERNamingStandardSchemaJson
            $Good = '{ "version": "1.0", "separator": "-", "sections": [ "groups" ], "segments": [ { "name": "kind", "values": [ "SG" ] } ] }'
            $Bad = '{ "version": "1.0", "seperator": "-", "sections": [ "groups" ], "segments": [ { "name": "kind" } ] }'
            Test-Json -Json $Good -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
            Test-Json -Json $Bad -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }
}
