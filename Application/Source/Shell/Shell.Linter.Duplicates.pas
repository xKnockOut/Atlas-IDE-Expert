unit Shell.Linter.Duplicates;

// Internals-Rolle Shell: --check-duplicates, die Kopien-Prüfung im Build. Routinen mit wortgleichem Rumpf in
// verschiedenen Units (TDuplicateBodies) über alle Dateien des Ziels wie bei --check (Ausschlüsse aus atlas.json,
// --units). Mindestlänge und weitere Ausschlüsse aus den Optionen der Regel duplicate-routine-body (minLines,
// exclude). Bekannte Gruppen stehen in der Baseline (--baseline, sonst atlas-duplicates.json neben atlas.json);
// --update-baseline schreibt sie neu.
//
// Exit-Code 1, wenn eine Gruppe neu ist, eine bekannte Gruppe eine weitere Kopie bekommen hat oder die Baseline
// Einträge enthält, die es nicht mehr gibt (dann ließe sie eine entfernte Kopie unbemerkt wiederkommen). Die
// Baseline kann so nur schrumpfen; dass sie zwischen zwei Ständen nicht wächst, prüft Tools/Check-Baselines.ps1.
// 0 ohne Abweichung und nach --update-baseline, 3 bei Aufruf- und Lesefehlern.

interface

uses
  Atlas.Common.Metrics.DuplicateBodies,
  Atlas.Common.Metrics.DuplicateBaseline,
  Shell.CommandLine;

type
  TLinterDuplicates = class
  public const
    /// <summary>Name der Baseline neben atlas.json.</summary>
    cBaselineName = 'atlas-duplicates.json';
  public
    /// <summary>--check-duplicates, siehe Kopf der Unit.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>Bericht als Text: neue Kopien, tote Einträge, Zusammenfassung.</summary>
    class function RenderText(const AComparison: TDuplicateComparison; AGroups: Integer): string; static;
    /// <summary>Bericht als JSON.</summary>
    class function RenderJson(const AComparison: TDuplicateComparison; AGroups: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Filter,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Output,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Lsp.ServerActivity,
  Atlas.Text.Json,
  Shell.Linter.Output,
  Shell.Linter.Settings,
  Shell.Linter.Files,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterDuplicatesText = (NewGroup, FurtherCopy, NewMark, Stale, Summary, Advice, StaleAdvice, Written,
    BaselineUnreadable, MinLinesDiffer, BadFormat);
{$SCOPEDENUMS OFF}

const
  cRuleId = 'duplicate-routine-body';
  cTexts: array[TLinterDuplicatesText] of TAtlasText = (
    (De: 'Neue Kopie: %d Zeilen, %d Fassungen'; En: 'New copy: %d lines, %d versions'),
    (De: 'Weitere Kopie einer bekannten Gruppe: %d Zeilen, %d Fassungen';
    En: 'Further copy of a known group: %d lines, %d versions'),
    (De: ' (neu)'; En: ' (new)'),
    (De: 'Nicht mehr vorhanden, aber in der Baseline: %s'; En: 'No longer present, but in the baseline: %s'),
    (De: '%d Gruppen wortgleicher Rümpfe, %d bekannt; %d mit neuen Kopien, %d tote Einträge der Baseline';
    En: '%d groups of identical bodies, %d known; %d with new copies, %d dead baseline entries'),
    (De: 'Neue Kopien zusammenlegen (gemeinsame Routine), nicht in die Baseline aufnehmen.';
    En: 'Merge new copies into a shared routine instead of adding them to the baseline.'),
    (De: 'Baseline nach dem Entfernen von Kopien neu schreiben: AtlasServer --check <Ziel> --check-duplicates ' +
    '--update-baseline';
    En: 'Rewrite the baseline after removing copies: AtlasServer --check <target> --check-duplicates ' +
    '--update-baseline'),
    (De: 'Baseline geschrieben: %s (%d Gruppen, %d Fassungen, %d Dateien)';
    En: 'Baseline written: %s (%d groups, %d versions, %d files)'),
    (De: 'Baseline "%s" nicht lesbar: %s'; En: 'Baseline "%s" not readable: %s'),
    (De: 'Mindestlänge der Baseline (%d) passt nicht zu minLines (%d); mit --update-baseline neu schreiben';
    En: 'Minimum length of the baseline (%d) does not match minLines (%d); rewrite it with --update-baseline'),
    (De: '--check-duplicates gibt es mit --format text oder json';
    En: '--check-duplicates exists with --format text or json'));

/// <summary>Optionen der Regel aus atlas.json als JSON-Text; '' ohne.</summary>
function RuleOptionsOf(const ASettings: TServerSettings): string;
var
  mRule: TRuleSetting;
begin
  Result := '';
  for mRule in ASettings.Rules do
  begin
    if SameText(mRule.Id, cRuleId) then
    begin
      Result := mRule.Options;
    end;
  end;
end;

function MatchesAny(const APatterns: TArray<string>; const APath: string): Boolean;
var
  mPattern: string;
begin
  for mPattern in APatterns do
  begin
    if MatchesGlob(mPattern, APath) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Rümpfe aller Quelltexte von AFiles, die weder atlas.json noch AExclude ausschließt.</summary>
function UnitsOf(const AFiles: TArray<string>; const ARoot: string; const ASettings: TServerSettings;
  const AFilter: TFindingFilter; const AExclude: TArray<string>): TArray<TDuplicateBodyUnit>;
var
  mIndex: Integer;
  mRelative, mText: string;
begin
  Result := nil;
  for mIndex := 0 to High(AFiles) do
  begin
    TServerActivity.Shared.SetProgress(mIndex, Length(AFiles));
    mRelative := StringReplace(ExtractRelativePath(IncludeTrailingPathDelimiter(ARoot), AFiles[mIndex]), '\', '/',
      [rfReplaceAll]);
    if ASettings.IsExcluded(mRelative) or MatchesAny(AExclude, mRelative) or not AFilter.AcceptsFile(mRelative) or
      not TLinterFiles.ReadText(AFiles[mIndex], mText) then
    begin
      Continue;
    end;
    Result := Result + [TDuplicateBodyUnit.Create(mRelative, TDuplicateBodies.ForText(mText))];
  end;
  TServerActivity.Shared.SetProgress(Length(AFiles), Length(AFiles));
end;

function BaselinePathOf(const AOptions: TCommandLineOptions; const AConfigRoot: string): string;
begin
  Result := AOptions.BaselineFile;
  if Result = '' then
  begin
    Result := TPath.Combine(AConfigRoot, TLinterDuplicates.cBaselineName);
  end;
end;

/// <summary>Baseline aus APath, leer ohne Datei; False mit Meldung, wenn sie nicht lesbar ist.</summary>
function LoadBaseline(const APath: string; AMinLines: Integer; out ABaseline: TDuplicateBaseline): Boolean;
var
  mFormat: TFileFormat;
begin
  ABaseline := TDuplicateBaseline.FromGroups(nil, AMinLines);
  if not TFile.Exists(APath) then
  begin
    Exit(True);
  end;
  try
    ABaseline := TDuplicateBaseline.Parse(TFileEncoding.LoadFromFile(APath, mFormat));
  except
    on E: Exception do
    begin
      TLinterOutput.Error(cTexts[TLinterDuplicatesText.BaselineUnreadable].Fmt([APath, E.Message]));
      Exit(False);
    end;
  end;
  Result := ABaseline.MinLines = AMinLines;
  if not Result then
  begin
    TLinterOutput.Error(cTexts[TLinterDuplicatesText.MinLinesDiffer].Fmt([ABaseline.MinLines, AMinLines]));
  end;
end;

function IsNew(const ACopies: TDuplicateNewCopies; const AKey: string): Boolean;
var
  mKey: string;
begin
  for mKey in ACopies.NewMembers do
  begin
    if SameText(mKey, AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function StaleCount(const AComparison: TDuplicateComparison): Integer;
var
  mGroup: TDuplicateBaselineGroup;
begin
  Result := 0;
  for mGroup in AComparison.Stale do
  begin
    Inc(Result, Length(mGroup.Members));
  end;
end;

{ TLinterDuplicates }

class function TLinterDuplicates.RenderText(const AComparison: TDuplicateComparison; AGroups: Integer): string;
var
  mBuilder: TStringBuilder;
  mCopies: TDuplicateNewCopies;
  mMember: TDuplicateBodyMember;
  mStale: TDuplicateBaselineGroup;
  mKey, mMark: string;
  mHead: TLinterDuplicatesText;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mCopies in AComparison.NewCopies do
    begin
      mHead := TLinterDuplicatesText.FurtherCopy;
      if mCopies.NewGroup then
      begin
        mHead := TLinterDuplicatesText.NewGroup;
      end;
      mBuilder.Append(cTexts[mHead].Fmt([mCopies.Group.BodyLines, Length(mCopies.Group.Members)])).Append(#10);
      for mMember in mCopies.Group.Members do
      begin
        mMark := '';
        if IsNew(mCopies, mMember.Key) then
        begin
          mMark := cTexts[TLinterDuplicatesText.NewMark].Text;
        end;
        mBuilder.AppendFormat('  %s:%d %s%s', [mMember.Path, mMember.Line, mMember.Routine, mMark]).Append(#10);
      end;
    end;
    for mStale in AComparison.Stale do
    begin
      for mKey in mStale.Members do
      begin
        mBuilder.Append(cTexts[TLinterDuplicatesText.Stale].Fmt([mKey])).Append(#10);
      end;
    end;
    mBuilder.Append(cTexts[TLinterDuplicatesText.Summary].Fmt([AGroups, AComparison.KnownGroups,
      Length(AComparison.NewCopies), StaleCount(AComparison)])).Append(#10);
    if Length(AComparison.NewCopies) > 0 then
    begin
      mBuilder.Append(cTexts[TLinterDuplicatesText.Advice].Text).Append(#10);
    end;
    if Length(AComparison.Stale) > 0 then
    begin
      mBuilder.Append(cTexts[TLinterDuplicatesText.StaleAdvice].Text).Append(#10);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function CopiesJson(const ACopies: TDuplicateNewCopies): string;
var
  mMembers: TArray<string>;
  mMember: TDuplicateBodyMember;
begin
  mMembers := nil;
  for mMember in ACopies.Group.Members do
  begin
    mMembers := mMembers + [Format('{"path": %s, "routine": %s, "line": %d, "new": %s}',
      [TJsonText.Quote(mMember.Path), TJsonText.Quote(mMember.Routine), mMember.Line,
      LowerCase(BoolToStr(IsNew(ACopies, mMember.Key), True))])];
  end;
  Result := Format('{"hash": %s, "lines": %d, "newGroup": %s, "members": [%s]}', [TJsonText.Quote(ACopies.Group.Hash),
    ACopies.Group.BodyLines, LowerCase(BoolToStr(ACopies.NewGroup, True)), string.Join(', ', mMembers)]);
end;

class function TLinterDuplicates.RenderJson(const AComparison: TDuplicateComparison; AGroups: Integer): string;
var
  mCopies: TArray<string>;
  mStale: TArray<string>;
  mIndex: Integer;
begin
  mCopies := nil;
  for mIndex := 0 to High(AComparison.NewCopies) do
  begin
    mCopies := mCopies + [CopiesJson(AComparison.NewCopies[mIndex])];
  end;
  mStale := nil;
  for mIndex := 0 to High(AComparison.Stale) do
  begin
    mStale := mStale + [Format('{"hash": %s, "members": %s}', [TJsonText.Quote(AComparison.Stale[mIndex].Hash),
      TJsonText.List(AComparison.Stale[mIndex].Members)])];
  end;
  Result := Format('{"groups": %d, "known": %d, "newCopies": [%s], "stale": [%s]}'#10, [AGroups,
    AComparison.KnownGroups, string.Join(', ', mCopies), string.Join(', ', mStale)]);
end;

/// <summary>Prüfung bzw. --update-baseline über die Dateien des Ziels.</summary>
function Execute(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget): Integer;
var
  mSettings: TServerSettings;
  mRuleOptions, mRoot, mBaselinePath: string;
  mMinLines: Integer;
  mFiles: TArray<string>;
  mSources: TCheckSourceFunc;
  mUnits: TArray<TDuplicateBodyUnit>;
  mGroups: TArray<TDuplicateBodyGroup>;
  mBaseline: TDuplicateBaseline;
  mComparison: TDuplicateComparison;
begin
  mSettings := TLinterSettings.Load(ATarget.ConfigRoot);
  TFileEncodingDefaults.SetFolder(ATarget.ConfigRoot, mSettings.DefaultEncoding);
  mRuleOptions := RuleOptionsOf(mSettings);
  mMinLines := TRuleOptions.Int(mRuleOptions, 'minLines', TDuplicateBodies.cMinBodyLines);
  mFiles := TLinterFiles.Collect(AOptions.CheckTarget, mSettings, mRoot, mSources);
  mUnits := UnitsOf(mFiles, mRoot, mSettings, TLinterSettings.FilterOf(AOptions),
    TRuleOptions.Strings(mRuleOptions, 'exclude', nil));
  mGroups := TDuplicateBodies.Find(mUnits, mMinLines);
  mBaselinePath := BaselinePathOf(AOptions, ATarget.ConfigRoot);
  if AOptions.UpdateBaseline then
  begin
    mBaseline := TDuplicateBaseline.FromGroups(mGroups, mMinLines);
    TLinterOutput.SaveUtf8(mBaselinePath, mBaseline.ToJson);
    TLinterOutput.Error(cTexts[TLinterDuplicatesText.Written].Fmt([mBaselinePath, Length(mBaseline.Groups),
      mBaseline.MemberCount, Length(mUnits)]));
    Exit(TFindingsOutput.cExitClean);
  end;
  if not LoadBaseline(mBaselinePath, mMinLines, mBaseline) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  mComparison := mBaseline.Compare(mGroups);
  if AOptions.CheckFormat = TFindingsFormat.Json then
  begin
    TLinterOutput.Write(AOptions, TLinterDuplicates.RenderJson(mComparison, Length(mGroups)));
  end
  else
  begin
    TLinterOutput.Write(AOptions, TLinterDuplicates.RenderText(mComparison, Length(mGroups)));
  end;
  Result := TFindingsOutput.cExitClean;
  if not mComparison.Clean then
  begin
    Result := TFindingsOutput.cExitFindings;
  end;
end;

class function TLinterDuplicates.Run(const AOptions: TCommandLineOptions): Integer;
var
  mTarget: TLinterTarget;
begin
  TLinterOutput.Warnings(AOptions);
  if not (AOptions.CheckFormat in [TFindingsFormat.Text, TFindingsFormat.Json]) then
  begin
    TLinterOutput.Error(cTexts[TLinterDuplicatesText.BadFormat].Text);
    Exit(TFindingsOutput.cExitFailure);
  end;
  if not TLinterTarget.Resolve(AOptions.CheckTarget, mTarget) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  try
    Result := Execute(AOptions, mTarget);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.cExitFailure;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Duplicates', cTexts);

end.
