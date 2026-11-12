unit Atlas.Common.Configuration.Internals.GeneralOptions;

// Allgemeine Abschnitte von atlas.json: Delphi-Version, Sprache, Kodierung,
// Projekt, Konfiguration, Plattform, Speicher und Zeitlimit, Protokoll,
// server, diagnostics, experimental sowie die Editorbefehle completeBlocks,
// slashCommands, usesCommand, sortUses, usesKeep und deadCode.

interface

uses
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Abschnitte dieser Unit.</summary>
function GeneralSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TGeneralOptionsText = (UnknownDelphiVersionExpectedE, UnknownDelphiVersionExpectedE2, AllowedAreDeEnAnd,
    UnknownEncodingExpectedUtf8, MemoryBudgetMbMustBeAWhole, RequestTimeoutMsMustBeAWhole, AllowedAreDebugInfoWarning,
    DiagnosticsLogDaysMustBeA, AllowedAreTrueFalseAlphabetic, UsesKeepMustBeAList, DeadCodeMustBeAList,
    SlashCommandsDisabledMustBeA);

const
  cTexts: array[TGeneralOptionsText] of TAtlasText = (
    (De: 'Unbekannte Delphi-Version; erwartet z. B. "13" oder "37.0" für Delphi 13, "12" oder "23.0" für Delphi 12';
     En: 'Unknown Delphi version; expected e.g. "13" or "37.0" for Delphi 13, "12" or "23.0" for Delphi 12'),
    (De: 'Unbekannte Delphi-Version; erwartet z. B. "12" oder "23.0" für Delphi 12, "11" oder "22.0" für Delphi 11';
     En: 'Unknown Delphi version; expected e.g. "12" or "23.0" for Delphi 12, "11" or "22.0" for Delphi 11'),
    (De: 'Erlaubt sind "de", "en" und "" (wie die IDE)'; En: 'Allowed are "de", "en" and "" (like the IDE)'),
    (De: 'Unbekannte Kodierung; erwartet "utf-8" oder eine ANSI-Codepage wie "1252" oder "windows-1250"';
     En: 'Unknown encoding; expected "utf-8" or an ANSI code page like "1252" or "windows-1250"'),
    (De: '"memoryBudgetMb" muss eine ganze Zahl ab 0 sein'; En: '"memoryBudgetMb" must be a whole number from 0'),
    (De: '"requestTimeoutMs" muss eine ganze Zahl ab 1000 sein';
     En: '"requestTimeoutMs" must be a whole number from 1000'),
    (De: 'Erlaubt sind "debug", "info", "warning" und "error"';
     En: 'Allowed are "debug", "info", "warning" and "error"'),
    (De: '"diagnostics.logDays" muss eine ganze Zahl von 1 bis 365 sein';
     En: '"diagnostics.logDays" must be a whole number from 1 to 365'),
    (De: 'Erlaubt sind true, false, "alphabetic" und "namespace"';
     En: 'Allowed are true, false, "alphabetic" and "namespace"'),
    (De: '"usesKeep" muss eine Liste von Unit-Namen sein'; En: '"usesKeep" must be a list of unit names'),
    (De: '"deadCode.%s" muss eine Liste von Texten sein'; En: '"deadCode.%s" must be a list of texts'),
    (De: '"slashCommands.disabled" muss eine Liste von Befehlsnamen sein';
     En: '"slashCommands.disabled" must be a list of command names'));

{$SCOPEDENUMS OFF}

{ delphiVersion, minDelphiVersion }

/// <summary>BDS-Version aus AText ('' bleibt ''); False mit Fehler AMessage, wenn sie unbekannt ist.</summary>
function ReadVersion(AReader: TConfigurationReader; ANode: TJsonNode; const AName, AMessage: string;
  out AVersion: string): Boolean;
var
  mText: string;
begin
  AVersion := '';
  Result := AReader.ExpectString(ANode, AName, mText);
  if Result and (mText <> '') then
  begin
    AVersion := BdsVersionOf(mText);
    Result := AVersion <> '';
    if not Result then
    begin
      AReader.ReportNode(ANode, AMessage);
    end;
  end;
end;

procedure ReadDelphiVersion(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mVersion: string;
begin
  if ReadVersion(AReader, ANode, 'delphiVersion', cTexts[TGeneralOptionsText.UnknownDelphiVersionExpectedE].Text,
    mVersion) then
  begin
    ASettings.DelphiVersion := mVersion;
    if mVersion <> '' then
    begin
      ASettings.DelphiVersionRange := TTextRange.Create(AReader.PositionAt(ANode.Start),
        AReader.PositionAt(ANode.Stop));
    end;
  end;
end;

procedure TakeDelphiVersion(const ASource: TServerSettings; const AFileText: string;
  var ATarget: TServerSettings);
begin
  ATarget.DelphiVersion := ASource.DelphiVersion;
  ATarget.DelphiVersionRange := ASource.DelphiVersionRange;
end;

procedure ReadMinDelphiVersion(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mVersion: string;
begin
  if ReadVersion(AReader, ANode, 'minDelphiVersion', cTexts[TGeneralOptionsText.UnknownDelphiVersionExpectedE2].Text,
    mVersion) then
  begin
    ASettings.MinDelphiVersion := mVersion;
  end;
end;

procedure TakeMinDelphiVersion(const ASource: TServerSettings; const AFileText: string;
  var ATarget: TServerSettings);
begin
  ATarget.MinDelphiVersion := ASource.MinDelphiVersion;
end;

{ language, encoding }

procedure ReadLanguage(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if not AReader.ExpectString(ANode, 'language', mText) then
  begin
    Exit;
  end;
  if MatchStr(mText, ['', 'de', 'en']) then
  begin
    ASettings.Language := mText;
  end
  else
  begin
    AReader.ReportNode(ANode, cTexts[TGeneralOptionsText.AllowedAreDeEnAnd].Text);
  end;
end;

procedure TakeLanguage(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Language := ASource.Language;
end;

procedure ReadEncoding(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if AReader.ExpectString(ANode, 'encoding', mText) and
    not TFileEncoding.ParseCodePage(mText, ASettings.DefaultEncoding) then
  begin
    ASettings.DefaultEncoding := TFileEncoding.cUtf8CodePage;
    AReader.ReportNode(ANode, cTexts[TGeneralOptionsText.UnknownEncodingExpectedUtf8].Text);
  end;
end;

procedure TakeEncoding(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.DefaultEncoding := ASource.DefaultEncoding;
end;

{ project, config, platform }

procedure ReadProject(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if AReader.ExpectString(ANode, 'project', mText) then
  begin
    ASettings.Project := mText;
  end;
end;

procedure TakeProject(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Project := ASource.Project;
end;

procedure ReadConfig(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if AReader.ExpectString(ANode, 'config', mText) then
  begin
    ASettings.Config := mText;
  end;
end;

procedure TakeConfig(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Config := ASource.Config;
end;

procedure ReadPlatform(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if AReader.ExpectString(ANode, 'platform', mText) then
  begin
    ASettings.Platform := mText;
  end;
end;

procedure TakePlatform(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.Platform := ASource.Platform;
end;

{ memoryBudgetMb, requestTimeoutMs }

procedure ReadMemoryBudget(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(ANode, 0, MaxInt, cTexts[TGeneralOptionsText.MemoryBudgetMbMustBeAWhole].Text,
    ASettings.MemoryBudgetMb);
end;

procedure TakeMemoryBudget(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.MemoryBudgetMb := ASource.MemoryBudgetMb;
end;

procedure ReadRequestTimeout(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(ANode, 1000, MaxInt, cTexts[TGeneralOptionsText.RequestTimeoutMsMustBeAWhole].Text,
    ASettings.RequestTimeoutMs);
end;

procedure TakeRequestTimeout(const ASource: TServerSettings; const AFileText: string;
  var ATarget: TServerSettings);
begin
  ATarget.RequestTimeoutMs := ASource.RequestTimeoutMs;
end;

{ logLevel, logFile, traceFile }

procedure ReadLogLevel(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if not AReader.ExpectString(ANode, 'logLevel', mText) then
  begin
    Exit;
  end;
  if MatchStr(mText, ['debug', 'info', 'warning', 'error']) then
  begin
    ASettings.LogLevel := mText;
  end
  else
  begin
    AReader.ReportNode(ANode, cTexts[TGeneralOptionsText.AllowedAreDebugInfoWarning].Text);
  end;
end;

procedure TakeLogLevel(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.LogLevel := ASource.LogLevel;
end;

procedure ReadLogFile(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if AReader.ExpectString(ANode, 'logFile', mText) then
  begin
    ASettings.LogFile := mText;
  end;
end;

procedure TakeLogFile(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.LogFile := ASource.LogFile;
end;

procedure ReadTraceFile(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mText: string;
begin
  if AReader.ExpectString(ANode, 'traceFile', mText) then
  begin
    ASettings.TraceFile := mText;
  end;
end;

procedure TakeTraceFile(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.TraceFile := ASource.TraceFile;
end;

{ server, diagnostics, experimental }

procedure ReadServer(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'server', [TFlagOption.Create('crashCases', ASettings.ServerCrashCases),
    TFlagOption.Create('crashSkip', ASettings.ServerCrashSkip),
    TFlagOption.Create('statusFile', ASettings.ServerStatusFile)], [], ASettings);
end;

procedure TakeServer(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.ServerCrashCases := ASource.ServerCrashCases;
  ATarget.ServerCrashSkip := ASource.ServerCrashSkip;
  ATarget.ServerStatusFile := ASource.ServerStatusFile;
end;

procedure ReadLogDays(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
begin
  AReader.ExpectInteger(AValue, 1, 365, cTexts[TGeneralOptionsText.DiagnosticsLogDaysMustBeA].Text,
    ASettings.DiagnosticsLogDays);
end;

const
  cDiagnosticsMembers: array[0..0] of TMemberOption = ((Key: 'logDays'; Read: ReadLogDays));

procedure ReadDiagnostics(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'diagnostics', [TFlagOption.Create('log', ASettings.DiagnosticsLog),
    TFlagOption.Create('logMapFile', ASettings.DiagnosticsLogMapFile),
    TFlagOption.Create('usesCycleLive', ASettings.DiagnosticsUsesCycleLive),
    TFlagOption.Create('usesCycleImplementation', ASettings.DiagnosticsUsesCycleImplementation),
    TFlagOption.Create('librarySources', ASettings.DiagnosticsLibrarySources)], cDiagnosticsMembers, ASettings);
end;

procedure TakeDiagnostics(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.DiagnosticsLog := ASource.DiagnosticsLog;
  ATarget.DiagnosticsLogDays := ASource.DiagnosticsLogDays;
  ATarget.DiagnosticsLogMapFile := ASource.DiagnosticsLogMapFile;
  ATarget.DiagnosticsUsesCycleLive := ASource.DiagnosticsUsesCycleLive;
  ATarget.DiagnosticsUsesCycleImplementation := ASource.DiagnosticsUsesCycleImplementation;
  ATarget.DiagnosticsLibrarySources := ASource.DiagnosticsLibrarySources;
end;

procedure ReadExperimental(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'experimental', [TFlagOption.Create('enabled', ASettings.ExperimentalEnabled)], [],
    ASettings);
end;

procedure TakeExperimental(const ASource: TServerSettings; const AFileText: string;
  var ATarget: TServerSettings);
begin
  ATarget.ExperimentalEnabled := ASource.ExperimentalEnabled;
end;

{ completeBlocks, usesCommand, sortUses, usesKeep, deadCode }

procedure ReadCompleteBlocks(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'completeBlocks', [TFlagOption.Create('docComment', ASettings.CompleteBlocksDocComment)],
    [], ASettings);
end;

procedure TakeCompleteBlocks(const ASource: TServerSettings; const AFileText: string;
  var ATarget: TServerSettings);
begin
  ATarget.CompleteBlocksDocComment := ASource.CompleteBlocksDocComment;
end;

procedure ReadUsesCommand(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ExpectBoolean(ANode, 'usesCommand', ASettings.UsesCommand);
end;

procedure TakeUsesCommand(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.UsesCommand := ASource.UsesCommand;
end;

procedure ReadSortUses(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  // true/false wie bisher, "namespace" sortiert gruppiert nach Namespace (#284).
  if ANode.Kind = TJsonKind.Boolean_ then
  begin
    ASettings.SortUses := SameText(ANode.Value, 'true');
    ASettings.SortUsesByNamespace := False;
  end
  else if (ANode.Kind = TJsonKind.String_) and MatchText(ANode.Value, ['alphabetic', 'namespace']) then
  begin
    ASettings.SortUses := True;
    ASettings.SortUsesByNamespace := SameText(ANode.Value, 'namespace');
  end
  else
  begin
    AReader.ReportNode(ANode, cTexts[TGeneralOptionsText.AllowedAreTrueFalseAlphabetic].Text);
  end;
end;

procedure TakeSortUses(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.SortUses := ASource.SortUses;
  ATarget.SortUsesByNamespace := ASource.SortUsesByNamespace;
end;

procedure ReadUsesKeep(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mItems: TArray<string>;
begin
  if AReader.ExpectStrings(ANode, 'usesKeep', cTexts[TGeneralOptionsText.UsesKeepMustBeAList].Text, mItems) then
  begin
    ASettings.UsesKeep := mItems;
  end;
end;

procedure TakeUsesKeep(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.UsesKeep := ASource.UsesKeep;
end;

procedure ReadKeepList(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mItems: TArray<string>;
begin
  if not AReader.ExpectStrings(AValue, 'deadCode.' + AKey,
    cTexts[TGeneralOptionsText.DeadCodeMustBeAList].Fmt([AKey]), mItems) then
  begin
    Exit;
  end;
  if AKey = 'keepAttributes' then
  begin
    ASettings.DeadCodeKeepAttributes := mItems;
  end
  else
  begin
    ASettings.DeadCodeKeepPatterns := mItems;
  end;
end;

const
  cDeadCodeMembers: array[0..1] of TMemberOption = ((Key: 'keepAttributes'; Read: ReadKeepList),
    (Key: 'keepPatterns'; Read: ReadKeepList));

procedure ReadDeadCode(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'deadCode', [], cDeadCodeMembers, ASettings);
end;

procedure TakeDeadCode(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  ATarget.DeadCodeKeepAttributes := ASource.DeadCodeKeepAttributes;
  ATarget.DeadCodeKeepPatterns := ASource.DeadCodeKeepPatterns;
end;

{ slashCommands }

procedure ReadSlashDisabled(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mItems: TArray<string>;
begin
  if AReader.ExpectStrings(AValue, AKey, cTexts[TGeneralOptionsText.SlashCommandsDisabledMustBeA].Text,
    mItems) then
  begin
    ASettings.SlashCommandsDisabled := mItems;
  end;
end;

procedure ReadSlashText(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mText: string;
begin
  if not AReader.ExpectString(AValue, AKey, mText) then
  begin
    mText := '';
  end;
  if AKey = 'headerTemplate' then
  begin
    ASettings.SlashHeaderTemplate := mText;
  end
  else if AKey = 'logCall' then
  begin
    ASettings.SlashLogCall := mText;
  end
  else if AKey = 'componentPalette' then
  begin
    ASettings.SlashComponentPalette := mText;
  end
  else if AKey = 'todoOwner' then
  begin
    ASettings.SlashTodoOwner := mText;
  end
  else
  begin
    ASettings.SlashTodoCategory := mText;
  end;
end;

const
  cSlashMembers: array[0..5] of TMemberOption = ((Key: 'disabled'; Read: ReadSlashDisabled),
    (Key: 'headerTemplate'; Read: ReadSlashText), (Key: 'logCall'; Read: ReadSlashText),
    (Key: 'componentPalette'; Read: ReadSlashText), (Key: 'todoOwner'; Read: ReadSlashText),
    (Key: 'todoCategory'; Read: ReadSlashText));

procedure ReadSlashCommands(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
begin
  AReader.ReadObject(ANode, 'slashCommands', [TFlagOption.Create('enabled', ASettings.SlashCommands),
    TFlagOption.Create('sortUsesRemoveUnused', ASettings.SlashSortUsesRemoveUnused),
    TFlagOption.Create('enumHelper', ASettings.SlashEnumHelper),
    TFlagOption.Create('setHelper', ASettings.SlashSetHelper)], cSlashMembers, ASettings);
end;

procedure TakeSlashCommands(const ASource: TServerSettings; const AFileText: string;
  var ATarget: TServerSettings);
begin
  ATarget.SlashCommands := ASource.SlashCommands;
  ATarget.SlashCommandsDisabled := ASource.SlashCommandsDisabled;
  ATarget.SlashHeaderTemplate := ASource.SlashHeaderTemplate;
  ATarget.SlashLogCall := ASource.SlashLogCall;
  ATarget.SlashComponentPalette := ASource.SlashComponentPalette;
  ATarget.SlashTodoOwner := ASource.SlashTodoOwner;
  ATarget.SlashTodoCategory := ASource.SlashTodoCategory;
  ATarget.SlashSortUsesRemoveUnused := ASource.SlashSortUsesRemoveUnused;
  ATarget.SlashEnumHelper := ASource.SlashEnumHelper;
  ATarget.SlashSetHelper := ASource.SlashSetHelper;
end;

const
  cSections: array[0..21] of TConfigurationSection = (
    (Section: 'delphiVersion'; Read: ReadDelphiVersion; Take: TakeDelphiVersion),
    (Section: 'minDelphiVersion'; Read: ReadMinDelphiVersion; Take: TakeMinDelphiVersion),
    (Section: 'language'; Read: ReadLanguage; Take: TakeLanguage),
    (Section: 'encoding'; Read: ReadEncoding; Take: TakeEncoding),
    (Section: 'project'; Read: ReadProject; Take: TakeProject),
    (Section: 'config'; Read: ReadConfig; Take: TakeConfig),
    (Section: 'platform'; Read: ReadPlatform; Take: TakePlatform),
    (Section: 'memoryBudgetMb'; Read: ReadMemoryBudget; Take: TakeMemoryBudget),
    (Section: 'requestTimeoutMs'; Read: ReadRequestTimeout; Take: TakeRequestTimeout),
    (Section: 'logLevel'; Read: ReadLogLevel; Take: TakeLogLevel),
    (Section: 'logFile'; Read: ReadLogFile; Take: TakeLogFile),
    (Section: 'traceFile'; Read: ReadTraceFile; Take: TakeTraceFile),
    (Section: 'server'; Read: ReadServer; Take: TakeServer),
    (Section: 'diagnostics'; Read: ReadDiagnostics; Take: TakeDiagnostics),
    (Section: 'experimental'; Read: ReadExperimental; Take: TakeExperimental),
    (Section: 'completeBlocks'; Read: ReadCompleteBlocks; Take: TakeCompleteBlocks),
    (Section: 'usesCommand'; Read: ReadUsesCommand; Take: TakeUsesCommand),
    (Section: 'sortUses'; Read: ReadSortUses; Take: TakeSortUses),
    (Section: 'usesKeep'; Read: ReadUsesKeep; Take: TakeUsesKeep),
    (Section: 'deadCode'; Read: ReadDeadCode; Take: TakeDeadCode),
    (Section: 'slashCommands'; Read: ReadSlashCommands; Take: TakeSlashCommands),
    (Section: '$schema'; Read: nil; Take: nil)
  );

function GeneralSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.GeneralOptions', cTexts);

end.
