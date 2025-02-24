# ----------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Code generated by Microsoft (R) AutoRest Code Generator.Changes may cause incorrect behavior and will be lost If the code
# is regenerated.
# ----------------------------------------------------------------------------------

# Usage: 1. This script can be called by build.proj used in CI pipeline
#        2. Can be used to do static analysis in local env. Such as: .\tools\ExecuteCIStep.ps1 -StaticAnalysisSignature -TargetModule "Accounts;Compute"
#        3. Can run static analyis for all the module built in artifacts. Such as: .\tools\ExecuteCIStep.ps1 -StaticAnalysisSignature will run static analysis signature check for all the modules under artifacts/debug.
Param(
    [Switch]
    $Build,

    [String]
    $BuildAction='build',

    [String]
    $GenerateDocumentationFile,

    [String]
    $EnableTestCoverage,

    [Switch]
    $Test,

    [Switch]
    $StaticAnalysis,

    [Switch]
    $StaticAnalysisBreakingChange,

    [Switch]
    $StaticAnalysisDependency,

    [Switch]
    $StaticAnalysisSignature,

    [Switch]
    $StaticAnalysisHelp,

    [Switch]
    $StaticAnalysisUX,

    [String]
    $RepoArtifacts='artifacts',

    [String]
    $Configuration='Debug',

    [String]
    $TestFramework='netcoreapp2.2',

    [String]
    $TestOutputDirectory='artifacts/TestResults',

    [String]
    $StaticAnalysisOutputDirectory='artifacts/StaticAnalysisResults',

    [String]
    $TargetModule
)
$ErrorActionPreference = 'Stop'

If ($Build)
{
    $LogFile = "$RepoArtifacts/Build.Log"
    $buildCmdResult = "dotnet $BuildAction $RepoArtifacts/Azure.PowerShell.sln -c $Configuration -fl '/flp1:logFile=$LogFile;verbosity=quiet'"
    If ($GenerateDocumentationFile -eq "false")
    {
        $buildCmdResult += " -p:GenerateDocumentationFile=false"
    }
    if ($EnableTestCoverage -eq "true")
    {
        $buildCmdResult += " -p:TestCoverage=TESTCOVERAGE"
    }
    Invoke-Expression -Command $buildCmdResult

    If (Test-Path -Path "$RepoArtifacts/PipelineResult")
    {
        $LogContent = Get-Content $LogFile
        $BuildResultArray = @()
        ForEach ($Line In $LogContent)
        {
            $Position, $ErrorOrWarningType, $Detail = $Line.Split(": ")
            $Detail = Join-String -Separator ": " -InputObject $Detail
            If ($Position.Contains("src"))
            {
                $ModuleName = "Az." + $Position.Replace("\", "/").Split("src/")[1].Split('/')[0]
            }
            Else
            {
                $ModuleName = "dotnet"
            }
            $Type, $Code = $ErrorOrWarningType.Split(" ")
            $BuildResultArray += @{
                "Position" = $Position;
                "Module" = $ModuleName;
                "Type" = $Type;
                "Code" = $Code;
                "Detail" = $Detail
            }
        }

        #Region produce result.json for GitHub bot to comsume
        If ($IsWindows)
        {
            $OS = "Windows"
        }
        ElseIf ($IsLinux)
        {
            $OS = "Linux"
        }
        ElseIf ($IsMacOS)
        {
            $OS = "MacOS"
        }
        Else
        {
            $OS = "Others"
        }
        $Platform = "$($Env:PowerShellPlatform) - $OS"
        $Template = Get-Content "$PSScriptRoot/PipelineResultTemplate.json" | ConvertFrom-Json
        $ModuleBuildInfoList = @()
        $CIPlan = Get-Content "$RepoArtifacts/PipelineResult/CIPlan.json" | ConvertFrom-Json
        ForEach ($ModuleName In $CIPlan.build)
        {
            $BuildResultOfModule = $BuildResultArray | Where-Object { $_.Module -Eq "Az.$ModuleName" }
            If ($BuildResultOfModule.Length -Eq 0)
            {
                $ModuleBuildInfoList += @{
                    Module = "Az.$ModuleName";
                    Status = "Succeeded";
                    Content = "";
                }
            }
            Else
            {
                $Content = "|Type|Code|Position|Detail|`n|---|---|---|---|`n"
                $ErrorCount = 0
                ForEach ($BuildResult In $BuildResultOfModule)
                {
                    If ($BuildResult.Type -Eq "Error")
                    {
                        $ErrorTypeEmoji = "❌"
                        $ErrorCount += 1
                    }
                    ElseIf ($BuildResult.Type -Eq "Warning")
                    {
                        $ErrorTypeEmoji = "⚠️"
                    }
                    $Content += "|$ErrorTypeEmoji|$($BuildResult.Code)|$($BuildResult.Position)|$($BuildResult.Detail)|`n"
                }
                If ($ErrorCount -Eq 0)
                {
                    $Status = "Warning"
                }
                Else
                {
                    $Status = "Failed"
                }
                $ModuleBuildInfoList += @{
                    Module = "Az.$ModuleName";
                    Status = $Status;
                    Content = $Content;
                }
            }
        }
        $BuildDetail = @{
            Platform = $Platform;
            Modules = $ModuleBuildInfoList;
        }
        $Template.Build.Details += $BuildDetail

        $DependencyStepList = $Template | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object { $_ -Ne "build" }

        ForEach ($DependencyStep In $DependencyStepList)
        {
            $ModuleInfoList = @()
            ForEach ($ModuleName In $CIPlan.$DependencyStep)
            {
                $ModuleInfoList += @{
                    Module = "Az.$ModuleName";
                    Status = $DependencyStepStatus;
                    Content = "";
                }
            }
            $Detail = @{
                Modules = $ModuleInfoList;
            }
            $Template.$DependencyStep.Details += $Detail
        }

        ConvertTo-Json -Depth 10 -InputObject $Template | Out-File -FilePath "$RepoArtifacts/PipelineResult/PipelineResult.json"
        #EndRegion
    }
    Return
}

$CIPlanPath = "$RepoArtifacts/PipelineResult/CIPlan.json"
If (Test-Path $CIPlanPath)
{
    $CIPlan = Get-Content $CIPlanPath | ConvertFrom-Json
}
ElseIf (-Not $PSBoundParameters.ContainsKey("TargetModule"))
{
    $TargetModule = Get-ChildItem "$RepoArtifacts/$Configuration" | ForEach-Object { $_.Name.Replace("Az.", "") } | Join-String -Separator ';'
    $PSBoundParameters["TargetModule"] = $TargetModule
}

If ($Test -And (($CIPlan.test.Length -Ne 0) -Or ($PSBoundParameters.ContainsKey("TargetModule"))))
{
    dotnet test $RepoArtifacts/Azure.PowerShell.sln --filter "AcceptanceType=CheckIn&RunType!=DesktopOnly" --configuration $Configuration --framework $TestFramework --logger trx --results-directory $TestOutputDirectory
    Return
}

If ($StaticAnalysis)
{
    $Parameters = @{
        RepoArtifacts = $RepoArtifacts;
        StaticAnalysisOutputDirectory = $StaticAnalysisOutputDirectory;
        Configuration = $Configuration;
    }
    If ($PSBoundParameters.ContainsKey("TargetModule"))
    {
        $Parameters["TargetModule"] = $TargetModule
    }
    .("$PSScriptRoot/ExecuteCIStep.ps1") -StaticAnalysisBreakingChange @Parameters
    .("$PSScriptRoot/ExecuteCIStep.ps1") -StaticAnalysisDependency @Parameters
    .("$PSScriptRoot/ExecuteCIStep.ps1") -StaticAnalysisSignature @Parameters
    .("$PSScriptRoot/ExecuteCIStep.ps1") -StaticAnalysisHelp @Parameters
    .("$PSScriptRoot/ExecuteCIStep.ps1") -StaticAnalysisUX @Parameters
    Return
}

If ($StaticAnalysisBreakingChange)
{
    If ($PSBoundParameters.ContainsKey("TargetModule"))
    {
        $BreakingChangeCheckModuleList = $TargetModule
    }
    Else
    {
        $BreakingChangeCheckModuleList = Join-String -Separator ';' -InputObject $CIPlan.'breaking-change'
    }
    If ("" -Ne $BreakingChangeCheckModuleList)
    {
        Write-Host "Running static analysis for breaking change..."
        dotnet $RepoArtifacts/StaticAnalysis/StaticAnalysis.Netcore.dll -p $RepoArtifacts/$Configuration -r $StaticAnalysisOutputDirectory --analyzers breaking-change -u -m $BreakingChangeCheckModuleList
    }
    Return
}
If ($StaticAnalysisDependency)
{
    If ($PSBoundParameters.ContainsKey("TargetModule"))
    {
        $DependencyCheckModuleList = $TargetModule
    }
    Else
    {
        $DependencyCheckModuleList = Join-String -Separator ';' -InputObject $CIPlan.dependency
    }
    If ("" -Ne $DependencyCheckModuleList)
    {
        Write-Host "Running static analysis for dependency..."
        dotnet $RepoArtifacts/StaticAnalysis/StaticAnalysis.Netcore.dll -p $RepoArtifacts/$Configuration -r $StaticAnalysisOutputDirectory --analyzers dependency -u -m $DependencyCheckModuleList
        .($PSScriptRoot + "/CheckAssemblies.ps1") -BuildConfig $Configuration
    }
    Return
}

If ($StaticAnalysisSignature)
{
    If ($PSBoundParameters.ContainsKey("TargetModule"))
    {
        $SignatureCheckModuleList = $TargetModule
    }
    Else
    {
        $SignatureCheckModuleList = Join-String -Separator ';' -InputObject $CIPlan.signature
    }
    If ("" -Ne $SignatureCheckModuleList)
    {
        Write-Host "Running static analysis for signature..."
        dotnet $RepoArtifacts/StaticAnalysis/StaticAnalysis.Netcore.dll -p $RepoArtifacts/$Configuration -r $StaticAnalysisOutputDirectory --analyzers signature -u -m $SignatureCheckModuleList
    }
    Return
}

If ($StaticAnalysisHelp)
{
    If ($PSBoundParameters.ContainsKey("TargetModule"))
    {
        $HelpCheckModuleList = $TargetModule
    }
    Else
    {
        $HelpCheckModuleList = Join-String -Separator ';' -InputObject $CIPlan.help
    }
    If ("" -Ne $HelpCheckModuleList)
    {
        Write-Host "Running static analysis for help..."
        dotnet $RepoArtifacts/StaticAnalysis/StaticAnalysis.Netcore.dll -p $RepoArtifacts/$Configuration -r $StaticAnalysisOutputDirectory --analyzers help -u -m $HelpCheckModuleList
    }
    Return
}

If ($StaticAnalysisUX)
{
    If ($PSBoundParameters.ContainsKey("TargetModule"))
    {
        $UXModuleList = $TargetModule
    }
    Else
    {
        $UXModuleList = Join-String -Separator ';' -InputObject $CIPlan.ux
    }
    If ("" -Ne $UXModuleList)
    {
        Write-Host "Running static analysis for UX metadata..."
        .("$PSScriptRoot/StaticAnalysis/UXMetadataAnalyzer/PrepareUXMetadata.ps1") -RepoArtifacts $RepoArtifacts -Configuration $Configuration
        dotnet $RepoArtifacts/StaticAnalysis/StaticAnalysis.Netcore.dll -p $RepoArtifacts/$Configuration -r $StaticAnalysisOutputDirectory --analyzers ux -u -m $UXModuleList
    }
    Return
}
