$DesktopPath = [Environment]::GetFolderPath("Desktop")
$CurrentPath = Get-Location
$FimPath = $CurrentPath.ToString()
$KeyLocation = ""

Function CheckLocationType ($location) {
    If (Test-Path -Path $location -PathType Container) {return "folder"}
    ElseIF (Test-Path -Path $location -PathType Leaf) {return "file"}
}

Function CalculateFileHash($path) {
    return Get-FileHash -Path $path -Algorithm SHA512 
}

Function CheckFileHash($path, $hash) {
    #if file path / folder path has been deleted or removed
    If (-Not (Test-Path $path)){
        return "'$($path)': File/Folder not found. File/Folder has been renamed, removed or deleted."
    }
    #if path is directory, stop
    If(-Not (Test-Path -Path $path -PathType Leaf)){
        return ""
    }
    $currentFileHash = Get-FileHash -Path $path -Algorithm SHA512
    If ($currentFileHash.Hash -eq $hash) {
        return "'$($path)': Hash matched. File has not been modified."
    }
    return "'$($path)': Hash not matched. File has been modified."
}

Function CreateEncryptionKey() {
    if(Test-Path "$($CurrentPath)\encryption.key"){
        Write-Output "`nKey already exists. Skipping key creation. `n"
    } else {
        # Create an encryption key
        $EncryptionKeyBytes = New-Object Byte[] 32
        [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($EncryptionKeyBytes)
        $EncryptionKeyBytes | Out-File "$($CurrentPath)\encryption.key"
    }
}

Function EncryptText ($key, $value) {
    $EncryptionKeyData = Get-Content $key
    $Secure_String = ConvertTo-SecureString $value -AsPlainText -Force
    return ConvertFrom-SecureString -SecureString $Secure_String -Key $EncryptionKeyData
}

Function DecryptText ($key, $value) {
    $EncryptionKeyData = Get-Content $key
    $DecryptedData = ConvertTo-SecureString $value -Key $EncryptionKeyData
    #Convert this SecureString object to plain text
    $PlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DecryptedData))
    return $PlainText
}

Write-Output "FIM (File Integrity Monitoring Script) By sapkota.sushant00@gmail.com `n"
Write-Output "This script will help you keep track of your files, for unauthorized changes i.e. file modification and/or file location/name changes.`n"
Write-Output "Instructions:`n1. Create an encryption key to secure your baseline file.`n2. Create baseline for your file(s) (For multiple files, you can use the folder path).`n3. Check for changes whenever you want. (Again, for multiple files, use folder path.)`n"
Write-Output "`nNote:`n1. Make sure to run this script from a location that doesn't require admin privileges such as your Desktop.`n2. A baseline file stores the hash and path of your file(s) to notice file changes/modifications.`n3. The text in the baseline file will be encrypted by a key that you generate.`n4. Make sure only you have access to the baseline file and encryption key generated (I suggest you save them to a secure location such as your google drive, ssh server or any protected drives). You can use them later by importing via the script.`n5. I haven't added function to update file hashes/path. So, please use this script for files you do not frequently modify.`n"

Write-Output "A. Use default encryption key or create new if not present."
Write-Output "B. Use saved encryption key.`n"

do {
    $keyResponse = Read-Host -Prompt "Please enter A or B"
} until($keyResponse.ToUpper() -match "^A$|^B$")

if($keyResponse.ToUpper() -eq "A"){
    CreateEncryptionKey
    $KeyLocation = "$($CurrentPath)\encryption.key"
} Else {
    do{
        $previousKey = Read-Host -Prompt "`nPlease provide your saved encrytion key's full location"
        if($previousKey){
            if(-Not (Test-Path -Path $previousKey -PathType Leaf)) {
                Write-Output "Invalid location. Key not found."
            }else {
                if([IO.Path]::GetExtension($previousKey) -ne ".key") {
                    Write-Output "Invalid key. Please provide a correct location."
                } else {
                    $KeyLocation = $previousKey
                }
            }
        }
    } until($KeyLocation)
}

# Ask to select exisiting or new baseline
Write-Output "`nA. Use existing baseline file or create new if not present."
Write-Output "B. Use a your own saved baseline file.`n"

do {
    $baselineOption = Read-Host -Prompt "Please enter A or B"
} until ($baselineOption.ToUpper() -match "^A$|^B$")

# Check previous baseline option or create a new baseline
$baselinePath = ""
If ($baselineOption.ToUpper() -eq "B"){
    do {
        $proceed = ""
        $baselinePath = Read-Host -Prompt "Please enter the full location of the previous baseline txt file"
        If ($baselinePath) {
            If (Test-Path -Path $baselinePath -PathType Leaf) {
                If ([IO.Path]::GetExtension($baselinePath) -eq ".txt"){
                    $proceed = "true"
                } Else {Write-Output "`nInvalid file. Please provide a valid file location.`n"}
            } Else {Write-Output "`nInvalid Location. Please provide a valid file location.`n"}
        }
    } until($proceed)
} Else {
    If (-Not (Test-Path "$($FimPath)\fim_baseline.txt")){
        New-Item -Path $FimPath -Name "fim_baseline.txt"
    }
    $baselinePath = "$($FimPath)\fim_baseline.txt"
}

Write-Output "Please choose between the following options:`n"
Write-Output "A. Create baseline for file/files."
Write-Output "B. Check specific file(s) integrity."
Write-Output "C. Check integrity of all files in Baseline.`n"

do {
    $response = Read-Host -Prompt "Please enter A, B or C"
} until($response.ToUpper() -match "^A$|^B$|^C$")

#Load our baseline file and get all texts
$baselineTexts = Get-Content -Path $baselinePath    

#Only get files list if option A or B is selected
If ($response.ToUpper() -match "A|B"){
    # Loop until the user provides a valid existing path
    $files = ""
    $filesLists = [System.Collections.Generic.List[string]]::new()

    do {
        $files = Read-Host -Prompt "Enter the full path of a file or a folder containing your files"
        IF ($files){
            If (-Not (Test-Path $files)) {
                Write-Output "Invalid location. File/Folder doesn't exits."
                $files = ""
            } ElseIf (CheckLocationType($files) -eq "folder"){
                $filesInFolder = Get-ChildItem -Recurse $files -file  | Resolve-Path | ForEach-Object  {$_.Path -replace "^.*?::"}
                foreach ($f in $filesInFolder) {$filesLists.Add($f)}
                if($filesLists.Count -eq 0){
                    $files = ""
                    Write-Output "Invalid location. Folder is empty."
                }
            } Else {
                $filesLists.Add($files)
            }
        }
    } until ($files)

    If ($response.ToUpper() -eq "A") {
    #Encrypt and save if A is selected
        foreach ($f in $filesLists){
            $fileHash = CalculateFileHash($f)
            $EncryptedValue = EncryptText $KeyLocation "$($fileHash.Hash)-$($fileHash.Path)"
            Add-Content -Path $baselinePath -Value $EncryptedValue
        }
        Write-Output "Baseline created for file(s). Find your baseline file in $($CurrentPath)"
    }ElseIf ($response.ToUpper() -eq "B"){
        #To save results in file
        New-Item -Path $CurrentPath -Name "fim_results.txt" -Force
        #Decrypt and check if B is selected
        foreach ($f in $filesLists){
            $fileHash = CalculateFileHash($f)
            #Else decrypt and compare hash and path
            #File hash or path is modified, in this case
            foreach ($t in $baselineTexts){
                #Decrypt and check all value
                $DecryptedValue = DecryptText $KeyLocation $t
                $DecryptedValueSection = $DecryptedValue -split "-", 2
                If ($fileHash.Hash -eq $DecryptedValueSection[0] -and $fileHash.Path -eq $DecryptedValueSection[1]) {
                    Add-Content -Path "$($CurrentPath)\fim_results.txt" -Value "$($f): File hash matched. File has not been modified."
                }ElseIf ($fileHash.Hash -eq $DecryptedValueSection[0]) {
                    Add-Content -Path "$($CurrentPath)\fim_results.txt" -Value "$($f): File hash matched. File has not been modified, however has been renamed/moved/replaced."
                } ElseIf ($fileHash.Path -eq $DecryptedValueSection[1]) {
                    Add-Content -Path "$($CurrentPath)\fim_results.txt" -Value "$($f): File hash not matched. File has been modified, however has not been renamed/moved/replaced."
                }
            }
        }
        Add-Content -Path "$($CurrentPath)\fim_results.txt" -Value "`n`nNote: If you see any specified file(s) missing above, either they were not registered in the baseline or were both modified and renamed/moved/replaced."
        Write-Output "Results of the integrity check are saved in $($CurrentPath)\fim_results.txt"
    }
} ElseIf ($response.ToUpper() -eq "C") {
    #To save results in file
    New-Item -Path $CurrentPath -Name "fim_results.txt" -Force
    foreach ($t in $baselineTexts){
        #Decrypt and check all value
        $DecryptedValue = DecryptText $KeyLocation $t
        $DecryptedValueSection = $DecryptedValue -split "-", 2
        Add-Content -Path "$($CurrentPath)\fim_results.txt" -Value $(CheckFileHash $DecryptedValueSection[1] $DecryptedValueSection[0])
    }
    Write-Output "Results of the integrity check are saved in $($CurrentPath)\fim_results.txt"
    # Ask if to read all files in Baseline, Folder directory or file provided
    # Read from the Baseline file seperate into array
    # Encrpyt  with key
    # Check the hash of each file with the file path
    # Check if the hash for any existing file matches here to label rename or replaced
}