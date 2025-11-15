param(
    [string]$DllPath,
    [string]$OutputHeaderPath
)

$assemblyBytes = [System.IO.File]::ReadAllBytes($DllPath)
$assembly = [System.Reflection.Assembly]::Load($assemblyBytes)
$type = $assembly.GetType('GeneratedHeader')
$field = $type.GetField('Header', [System.Reflection.BindingFlags] 'Public,Static')
$value = $field.GetValue($null)
Set-Content -Path $OutputHeaderPath -Value $value