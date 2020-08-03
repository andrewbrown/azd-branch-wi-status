# TODO : 
# - Handle when user is not already logged into Azure DevOps
# - Read these values in from Join-Path -Path "${Env:USERPROFILE} -ChildPath ".azd", if it exists
# - If the file does not exist or some values are missing, read them in from the host.
# - Write any new values back to ".azd"
# - Handle $PAT as a secure string
# - Add README with more details on what this script is doing
#
# Resources that may be useful:
# - Testing if an object has a specific property: https://stackoverflow.com/questions/26997511/how-can-you-test-if-an-object-has-a-specific-property
# - Handling secure input:
#   - https://social.technet.microsoft.com/Forums/office/en-US/f90bed75-475e-4f5f-94eb-60197efda6c6/prompt-for-password-without-using-getcredential-or-readhost-assecurestring-but-not-display-text?forum=winserverpowershell
#   - https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/convertfrom-securestring?view=powershell-7
# - Reading variables from a text file: https://stackoverflow.com/questions/12368142/powershell-retrieving-a-variable-from-a-text-file
#
$PRESENTER= Invoke-Expression "az account show | jq -r .user.name"
$ORGANIZATION="szonline"
$PROJECT="SiteZeus"
$PAT="..."

# From: https://makandracards.com/makandra/26903-git-listing-branches-with-their-latest-author
$gitBranchOutput = Invoke-Expression "git for-each-ref --format='%(committerdate:iso) %09 %(authorname) %09 %(refname)'"

$branches = ConvertFrom-Csv $gitBranchOutput -Delimiter "`t" -Header 'Date', 'Owner', 'Branch' |
    Sort-Object Owner, Date, Branch

foreach ($b in $branches) {

    # Convert the date/time information to date only, makes it simpler if opening the final CSV in Excel.
    $b.Date = [datetime]::Parse($b.Date).ToString('yyyy-MM-dd')

    if ($b.Branch -match '/(\d+)') {

        $workItem = $Matches.1
        $workItemRequestUri = "https://dev.azure.com/${ORGANIZATION}/${PROJECT}/_apis/wit/workitems?ids=${workItem}&api-version=5.1"

        try {
            # Technique for querying work items adapted from exampes at: https://jessicadeen.com/azure-devops-rest-api/
            $workItemJson = Invoke-RestMethod -Uri $workItemRequestUri -Headers @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($PRESENTER+":"+$PAT ))} -Method GET

            # JSON response includes fields like "System.State";
            # technique for accessing PowerShell properties with periods in their names taken from: https://blog.danskingdom.com/accessing-powershell-variables-with-periods-in-their-name/ 
            $workItemStatus = $workItemJson.value[0].fields.{System.State}

            $b | Add-Member -NotePropertyName "WorkItem" -NotePropertyValue $workItem
            $b | Add-Member -NotePropertyName "Status" -NotePropertyValue $workItemStatus
        } 
        catch {
            # Sometimes we get an error like this from Azure DevOps:
            #
            #   TF401232: Work item 9319 does not exist, or you do not have permissions to read
            #
            $b | Add-Member -NotePropertyName "WorkItem" -NotePropertyValue "Not Found (${workItem})"
            $b | Add-Member -NotePropertyName "Status" -NotePropertyValue "Not Applicable"
        }
    }
    else {
        $b | Add-Member -NotePropertyName "WorkItem" -NotePropertyValue "Not Found"
        $b | Add-Member -NotePropertyName "Status" -NotePropertyValue "Not Applicable"
    }
}

$branches | Export-Csv -Path "azd-branch-wi-status.csv" -NoTypeInformation
