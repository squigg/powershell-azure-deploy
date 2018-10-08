#Requires -Modules Utils
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="4.0.0" }

Describe 'ConvertTo-Hashtable' {

    $Object = [pscustomobject]@{
        Key = 'Value'
    }

    It 'Should convert a PSObject to a Hashtable' {
        $Result = ConvertTo-Hashtable $Object
        $Result.Key | Should -Be 'Value'
        $Result | Should -BeOfType System.Collections.Hashtable
    }
    It 'Should convert a PSObject to a Hashtable from Pipeline' {
        $Result = $Object | ConvertTo-Hashtable
        $Result | Should -BeOfType System.Collections.Hashtable
    }
    It 'Should convert an empty PSObject to a Hashtable' {
        $Object = [pscustomobject]@{}
        $Result = $Object | ConvertTo-Hashtable
        $Result | Should -BeOfType System.Collections.Hashtable
    }
}

Describe 'Limit-HashtableKey' {

    $Hash = @{
        Key = 'Value'
        Key2 = 'Value2'
        Key3 = 'Value3'
    }

    It 'Should leave only a single key in a Hashtable' {
        $Result = Limit-HashtableKey $Hash -Keys Key
        $Result.Keys | Should -HaveCount 1
        $Result.Key | Should -Be 'Value'
    }
    It 'Should leave only given keys in a Hashtable' {
        $Result = Limit-HashtableKey $Hash -Keys Key,Key3
        $Result.Keys | Should -HaveCount 2
        $Result.Key | Should -Be 'Value'
    }
    It 'Should accept hash from pipeline' {
        $Result = $Hash | Limit-HashtableKey  -Keys Key
        $Result.Keys | Should -HaveCount 1
    }
}

Describe 'Remove-HashtableKey' {

    $Hash = @{
        Key = 'Value'
        Key2 = 'Value2'
        Key3 = 'Value3'
    }

    It 'Should remove a single key from a Hashtable' {
        $Result = Remove-HashtableKey $Hash -Key Key
        $Result.ContainsKey("Key") | Should -Be $False
        $Result.Key2 | Should -Be 'Value2'
        $Result.Key3 | Should -Be 'Value3'
        $Result.Keys | Should -HaveCount 2
    }
    It 'Should remove a single key from a Hashtable from Pipeline' {
        $Result = $Hash | Remove-HashtableKey -Key Key
        $Result.Keys | Should -HaveCount 2
    }
    It 'Should remove multiple keys from a Hashtable' {
        $Result = Remove-HashtableKey $Hash -Keys Key,Key2
        $Result.ContainsKey("Key") | Should -Be $False
        $Result.ContainsKey("Key2") | Should -Be $False
        $Result.Key3 | Should -Be 'Value3'
        $Result.Keys | Should -HaveCount 1
    }
}

Describe 'Merge-Hashtable' {

    $Hash1 = @{
        Key = 'Value'
    }

    $Hash2 = @{
        Key2 = 'Value2'
    }

    $Hash3 = @{
        Key = 'DiffValue'
    }

    It 'Should merge hashes and retain all keys' {
        $Result = Merge-Hashtable $Hash1 $Hash2
        $Result.Keys | Should -HaveCount 2
        $Result.Key | Should -Be 'Value'
        $Result.Key2 | Should -Be 'Value2'
    }
    It 'Should overwrite hashes with duplicate keys from later hashes' {
        $Result = Merge-Hashtable $Hash1 $Hash3
        $Result.Keys | Should -HaveCount 1
        $Result.Key | Should -Be 'DiffValue'
    }
    It 'Should accept input from pipeline' {
        $Result = $Hash1,$Hash2 | Merge-Hashtable
        $Result.Keys | Should -HaveCount 2
    }
    It 'Should accept input from pipeline and args' {
        $Result = $Hash1 | Merge-Hashtable $Hash2
        $Result.Keys | Should -HaveCount 2
    }
}

Describe 'Compare-Hashtable' {

    $Hash = [hashtable]@{
        Key1 = 'Foo'
        Key2 = 'Bar'
    }

    $NestedHash = [hashtable]@{
        Key = [hashtable]@{ Name = 'Foo'}
    }

    $NestedObject = @{
        Key = [pscustomobject]@{ Name = 'Foo'}
    }

    $NestedArray = [hashtable]@{
        Key = 1,2,3
    }

    It 'Should compare hashes with simple values' {
        $Compare = [hashtable]@{
            Key1 = 'Foo'
            Key2 = 'Baz'
        }
        Compare-Hashtable $Hash $Hash.Clone() | Should -Be $True
        Compare-Hashtable $Hash $Compare | Should -Be $False
    }

    It 'Should compare hashes with different keys' {
        $Compare = [hashtable]@{
            Key1 = 'Foo'
        }
        Compare-Hashtable $Hash $Compare | Should -Be $False
    }

    It 'Should compare hashes with nested hash values' {
        $Hash = [hashtable]@{ Key = [hashtable]@{ Name = 'Foo'} }
        $CompareTrue = [hashtable]@{ Key = [hashtable]@{ Name = 'Foo'} }
        $CompareFalse = [hashtable]@{ Key = [hashtable]@{ Name = 'Bar'} }
        Compare-Hashtable $Hash $CompareTrue | Should -Be $True
        Compare-Hashtable $Hash $CompareFalse | Should -Be $False
    }

    It 'Should compare hashes with nested object values' {
        $Hash = [hashtable]@{ Key = [pscustomobject]@{ Name = 'Foo'} }
        $CompareTrue = [hashtable]@{ Key = [pscustomobject]@{ Name = 'Foo'} }
        $CompareFalse = [hashtable]@{ Key = [pscustomobject]@{ Name = 'Bar'} }
        Compare-Hashtable $Hash $CompareTrue | Should -Be $True
        Compare-Hashtable $Hash $CompareFalse | Should -Be $False
    }

    It 'Should compare hashes with nested array values' {
        $Hash = [hashtable]@{ Key = 1,2,3 }
        $CompareTrue = [hashtable]@{ Key = 1,2,3 }
        $CompareFalse = [hashtable]@{ Key = 1,2,4 }
        Compare-Hashtable $Hash $CompareTrue | Should -Be $True
        Compare-Hashtable $Hash $CompareFalse | Should -Be $False
    }
}
