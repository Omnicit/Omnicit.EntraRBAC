BeforeDiscovery {
    # One case per collection the handlers reconcile on an omitted key. Base declares every OTHER
    # pruning key of the item as an empty array, so the collection under test is the only one that
    # can be listed; Populated is a realistic declared value for that collection.
    $CollectionCases = @(
        @{ Section = 'groups';              Collection = 'members';       Base = '"displayName": "x"';                    Populated = '[ "u1" ]' }
        @{ Section = 'administrativeUnits'; Collection = 'members';       Base = '"displayName": "x", "scopedRoles": []'; Populated = '[ "u1" ]' }
        @{ Section = 'administrativeUnits'; Collection = 'scopedRoles';   Base = '"displayName": "x", "members": []';     Populated = '[ { "role": "User Administrator", "principal": "u1" } ]' }
        @{ Section = 'catalogs';            Collection = 'resources';     Base = '"displayName": "x"';                    Populated = '[ { "name": "g1", "type": "Group" } ]' }
        @{ Section = 'accessPackages';      Collection = 'resourceRoles'; Base = '"displayName": "x", "catalog": "c"';    Populated = '[ { "resource": "g1", "role": "Member" } ]' }
    )
}

BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop

    function Invoke-OmittedPrune {
        param([string]$Json)
        $Doc = $Json | ConvertFrom-Json
        InModuleScope $script:moduleName -Parameters @{ Doc = $Doc } {
            param($Doc)
            Get-OEROmittedPruneCollection -Document $Doc
        }
    }
}

Describe 'Get-OEROmittedPruneCollection' {
    Context 'the five collections that prune on an omitted key' {
        It 'lists an omitted <Collection> key in <Section> with its Section, Item, Path and Collection' -ForEach $CollectionCases {
            $R = @(Invoke-OmittedPrune -Json ('{ "version": "1.0", "' + $Section + '": [ { ' + $Base + ' } ] }'))
            $R.Count | Should -Be 1
            $R[0].Section    | Should -BeExactly $Section
            $R[0].Item       | Should -BeExactly 'x'
            $R[0].Path       | Should -BeExactly ('{0}[0]' -f $Section)
            $R[0].Collection | Should -BeExactly $Collection
        }

        It 'does not list <Section> <Collection> declared as an explicit null' -ForEach $CollectionCases {
            $R = @(Invoke-OmittedPrune -Json ('{ "version": "1.0", "' + $Section + '": [ { ' + $Base + ', "' + $Collection + '": null } ] }'))
            $R.Count | Should -Be 0
        }

        It 'does not list <Section> <Collection> declared as an empty array' -ForEach $CollectionCases {
            $R = @(Invoke-OmittedPrune -Json ('{ "version": "1.0", "' + $Section + '": [ { ' + $Base + ', "' + $Collection + '": [] } ] }'))
            $R.Count | Should -Be 0
        }

        It 'does not list <Section> <Collection> declared with entries' -ForEach $CollectionCases {
            $R = @(Invoke-OmittedPrune -Json ('{ "version": "1.0", "' + $Section + '": [ { ' + $Base + ', "' + $Collection + '": ' + $Populated + ' } ] }'))
            $R.Count | Should -Be 0
        }

        It 'returns records carrying exactly Section, Item, Path and Collection' {
            $R = @(Invoke-OmittedPrune -Json '{ "version": "1.0", "groups": [ { "displayName": "g1" } ] }')
            $R.Count | Should -Be 1
            @($R[0].PSObject.Properties.Name) | Should -BeExactly @('Section', 'Item', 'Path', 'Collection')
        }
    }

    Context 'dynamic groups and administrative units' {
        It 'does not list the omitted members of a group declared dynamic true' {
            $R = @(Invoke-OmittedPrune -Json '{ "version": "1.0", "groups": [ { "displayName": "g1", "dynamic": true, "membershipRule": "(user.department -eq \"IT\")" } ] }')
            $R.Count | Should -Be 0
        }

        It 'lists the omitted members of a group declared dynamic false' {
            $R = @(Invoke-OmittedPrune -Json '{ "version": "1.0", "groups": [ { "displayName": "g1", "dynamic": false } ] }')
            $R.Count | Should -Be 1
            $R[0].Collection | Should -BeExactly 'members'
            $R[0].Path       | Should -BeExactly 'groups[0]'
        }

        It 'lists the omitted scopedRoles but not the omitted members of an administrative unit declared dynamic true' {
            $R = @(Invoke-OmittedPrune -Json '{ "version": "1.0", "administrativeUnits": [ { "displayName": "au1", "dynamic": true, "membershipRule": "(user.department -eq \"IT\")" } ] }')
            $R.Count | Should -Be 1
            $R[0].Section    | Should -BeExactly 'administrativeUnits'
            $R[0].Item       | Should -BeExactly 'au1'
            $R[0].Collection | Should -BeExactly 'scopedRoles'
        }

        It 'lists both omitted keys of an administrative unit declared dynamic false, members first' {
            $R = @(Invoke-OmittedPrune -Json '{ "version": "1.0", "administrativeUnits": [ { "displayName": "au1", "dynamic": false } ] }')
            @($R | ForEach-Object { $_.Collection }) | Should -BeExactly @('members', 'scopedRoles')
        }
    }

    Context 'item labels and document shape' {
        It 'labels a template group, which has no displayName, by its path' {
            $R = @(Invoke-OmittedPrune -Json '{ "version": "1.0", "groups": [ { "template": "grp-{Region}", "tokens": { "Region": "EU" } } ] }')
            $R.Count | Should -Be 1
            $R[0].Item | Should -BeExactly 'groups[0]'
            $R[0].Path | Should -BeExactly 'groups[0]'
        }

        It 'lists nothing, and does not throw, for a document with no pruning section' {
            { Invoke-OmittedPrune -Json '{ "version": "1.0" }' } | Should -Not -Throw
            @(Invoke-OmittedPrune -Json '{ "version": "1.0" }').Count | Should -Be 0
        }

        It 'lists nothing, and does not throw, for a section that is <Shape>' -ForEach @(
            @{ Shape = 'null';      Value = 'null' }
            @{ Shape = 'an object'; Value = '{ "displayName": "g1" }' }
            @{ Shape = 'a string';  Value = '"g1"' }
        ) {
            $Json = '{ "version": "1.0", "groups": ' + $Value + ' }'
            { Invoke-OmittedPrune -Json $Json } | Should -Not -Throw
            @(Invoke-OmittedPrune -Json $Json).Count | Should -Be 0
        }

        It 'skips items that are not objects, without throwing, and keeps the document index of the rest' {
            $Json = '{ "version": "1.0", "groups": [ "g1", 3, null, { "displayName": "g2" } ] }'
            { Invoke-OmittedPrune -Json $Json } | Should -Not -Throw
            $R = @(Invoke-OmittedPrune -Json $Json)
            $R.Count | Should -Be 1
            $R[0].Item | Should -BeExactly 'g2'
            $R[0].Path | Should -BeExactly 'groups[3]'
        }

        It 'matches section and collection keys case-insensitively and reports the canonical section name' {
            $R = @(Invoke-OmittedPrune -Json '{ "Version": "1.0", "Groups": [ { "displayName": "g1", "Members": null }, { "displayName": "g2" } ] }')
            $R.Count | Should -Be 1
            $R[0].Section | Should -BeExactly 'groups'
            $R[0].Item    | Should -BeExactly 'g2'
            $R[0].Path    | Should -BeExactly 'groups[1]'
        }
    }

    Context 'output order' {
        It 'emits sections in engine order, items in document order, and an administrative unit members before scopedRoles' {
            # The JSON deliberately lists the sections in REVERSE engine order.
            $Json = '{ "version": "1.0", ' +
                '"accessPackages": [ { "displayName": "ap1", "catalog": "c1" } ], ' +
                '"catalogs": [ { "displayName": "c1" } ], ' +
                '"administrativeUnits": [ { "displayName": "au1" }, { "displayName": "au2", "members": [] } ], ' +
                '"groups": [ { "displayName": "g1" }, { "displayName": "g2" } ] }'
            $R = @(Invoke-OmittedPrune -Json $Json)
            @($R | ForEach-Object { '{0}|{1}|{2}' -f $_.Section, $_.Path, $_.Collection }) | Should -BeExactly @(
                'groups|groups[0]|members'
                'groups|groups[1]|members'
                'administrativeUnits|administrativeUnits[0]|members'
                'administrativeUnits|administrativeUnits[0]|scopedRoles'
                'administrativeUnits|administrativeUnits[1]|scopedRoles'
                'catalogs|catalogs[0]|resources'
                'accessPackages|accessPackages[0]|resourceRoles'
            )
        }
    }
}
