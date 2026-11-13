unit Atlas.Common.Lsp.AffectedTests.Report;

// Ausgabe der betroffenen Tests (#1353): Bericht für Menschen, JSON für atlas/affectedTests und
// get_affected_tests (auch zurückgelesen im Plugin) und das Argument --run:… für die Test-exe.

interface

uses
  System.JSON,
  Atlas.Common.Lsp.AffectedTests.Contract;

type
  TAffectedReport = class
  public
    /// <summary>text (oder leer), json, dunitx; False sonst.</summary>
    class function TryParseFormat(const AText: string; out AFormat: TAffectedFormat): Boolean; static;
    class function Render(const AResult: TAffectedResult; AFormat: TAffectedFormat): string; static;
    /// <summary>Bericht für Menschen.</summary>
    class function ToText(const AResult: TAffectedResult): string; static;
    /// <summary>Antwort von atlas/affectedTests und get_affected_tests mit format json; der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function ToJson(const AResult: TAffectedResult): TJSONObject; static;
    /// <summary>Argument --run:… für die Test-exe; '' bei allen Tests, ohne Tests oder wenn es zu lang wird
    /// (dann False).</summary>
    class function DUnitXArgument(const AResult: TAffectedResult; out AArgument: string): Boolean; static;
    /// <summary>Gelesenes Ergebnis von atlas/affectedTests (Plugin, Tests).</summary>
    class function FromJson(const AValue: TJSONValue): TAffectedResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Impact,
  Atlas.Text.DUnitX,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TAffectedReportText = (AllTestsNeeded, NoAffectedTestsComparedWith, AffectedTestsComparedWithDepth, Changed,
    LimitsReachedCheckWithGreater, WithoutInfluenceOnTestsFiles);

const
  cTexts: array[TAffectedReportText] of TAtlasText = (
    (De: 'Alle Tests nötig: %s.'; En: 'All tests needed: %s.'),
    (De: 'Keine betroffenen Tests gegenüber %s (Tiefe %d).'; En: 'No affected tests compared with %s (depth %d).'),
    (De: '%d betroffene Tests gegenüber %s (Tiefe %d), davon %d ganze Fixtures:';
     En: '%d affected tests compared with %s (depth %d), %d of them whole fixtures:'),
    (De: 'Geändert (%d):'; En: 'Changed (%d):'),
    (De: 'Grenzen erreicht: %s; mit größerer Tiefe oder allen Tests prüfen.';
     En: 'Limits reached: %s; check with greater depth or all tests.'),
    (De: 'Ohne Einfluss auf Tests: %d Dateien.'; En: 'Without influence on tests: %d files.'));

{$SCOPEDENUMS OFF}

class function TAffectedReport.TryParseFormat(const AText: string; out AFormat: TAffectedFormat): Boolean;
begin
  Result := True;
  if (AText = '') or SameText(AText, 'text') then
  begin
    AFormat := TAffectedFormat.Text;
  end
  else if SameText(AText, 'json') then
  begin
    AFormat := TAffectedFormat.Json;
  end
  else if SameText(AText, 'dunitx') then
  begin
    AFormat := TAffectedFormat.DUnitX;
  end
  else
  begin
    AFormat := TAffectedFormat.Text;
    Result := False;
  end;
end;

class function TAffectedReport.Render(const AResult: TAffectedResult; AFormat: TAffectedFormat): string;
var
  mJson: TJSONObject;
begin
  case AFormat of
    TAffectedFormat.Json:
      begin
        mJson := ToJson(AResult);
        try
          Result := mJson.ToJSON([]);
        finally
          mJson.Free;
        end;
      end;
    TAffectedFormat.DUnitX:
      if not DUnitXArgument(AResult, Result) then
      begin
        Result := '';
      end;
  else
    Result := ToText(AResult);
  end;
end;

class function TAffectedReport.DUnitXArgument(const AResult: TAffectedResult; out AArgument: string): Boolean;
var
  mRun: string;
begin
  AArgument := '';
  Result := True;
  if AResult.All or (Length(AResult.Tests) = 0) then
  begin
    Exit;
  end;
  mRun := string.Join(',', AResult.RunNames);
  if Length(mRun) > TDUnitXCommandLine.cMaxRunLength then
  begin
    Exit(False);
  end;
  AArgument := '--run:' + mRun;
end;

/// <summary>Kopf und Tests mit Gründen.</summary>
function TestLines(const AResult: TAffectedResult): TArray<string>;
var
  mTest: TAffectedTest;
  mReason: TAffectedReason;
  mFixtures: Integer;
begin
  if AResult.All then
  begin
    Exit(TArray<string>.Create(cTexts[TAffectedReportText.AllTestsNeeded].Fmt([AResult.AllReason])));
  end;
  if Length(AResult.Tests) = 0 then
  begin
    Exit(TArray<string>.Create(cTexts[TAffectedReportText.NoAffectedTestsComparedWith].Fmt([AResult.Base,
      AResult.Depth])));
  end;
  mFixtures := 0;
  for mTest in AResult.Tests do
  begin
    if mTest.Method = '' then
    begin
      Inc(mFixtures);
    end;
  end;
  Result := TArray<string>.Create(cTexts[TAffectedReportText.AffectedTestsComparedWithDepth].Fmt([Length(AResult.Tests),
    AResult.Base, AResult.Depth, mFixtures]));
  for mTest in AResult.Tests do
  begin
    Result := Result + ['  ' + mTest.Name];
    for mReason in mTest.Reasons do
    begin
      Result := Result + ['    ← ' + mReason.Text];
    end;
  end;
end;

function ChangeLines(const AResult: TAffectedResult): TArray<string>;
var
  mChange: TAffectedChange;
begin
  Result := nil;
  if Length(AResult.Changes) = 0 then
  begin
    Exit;
  end;
  Result := TArray<string>.Create('', cTexts[TAffectedReportText.Changed].Fmt([Length(AResult.Changes)]));
  for mChange in AResult.Changes do
  begin
    Result := Result + [Format('  %s (%s, %s)', [mChange.Text, mChange.Place, ExtractFileName(mChange.Source)])];
  end;
end;

function LimitNames(ALimits: TImpactLimits): TArray<string>;
var
  mLimit: TImpactLimit;
begin
  Result := nil;
  for mLimit := Low(TImpactLimit) to High(TImpactLimit) do
  begin
    if mLimit in ALimits then
    begin
      Result := Result + [TImpactAnalysis.LimitName(mLimit)];
    end;
  end;
end;

class function TAffectedReport.ToText(const AResult: TAffectedResult): string;
var
  mLines, mLimitNames: TArray<string>;
begin
  mLines := TestLines(AResult) + ChangeLines(AResult);
  if Length(AResult.Skipped) > 0 then
  begin
    mLines := mLines + ['', cTexts[TAffectedReportText.WithoutInfluenceOnTestsFiles].Fmt([Length(AResult.Skipped)])];
  end;
  mLimitNames := LimitNames(AResult.Limits);
  if mLimitNames <> nil then
  begin
    mLines := mLines + ['', cTexts[TAffectedReportText.LimitsReachedCheckWithGreater].Fmt([string.Join(', ',
      mLimitNames)])];
  end;
  if not AResult.All and (Length(AResult.Tests) > 0) then
  begin
    mLines := mLines + ['', 'run_tests tests: ' + string.Join(', ', AResult.RunNames)];
  end;
  Result := string.Join(sLineBreak, mLines) + sLineBreak;
end;

function StringsJson(const AValues: TArray<string>): TJSONArray;
var
  mValue: string;
begin
  Result := TJSONArray.Create;
  for mValue in AValues do
  begin
    Result.Add(mValue);
  end;
end;

function ReasonJson(const AReason: TAffectedReason): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('change', AReason.Change);
  Result.AddPair('path', StringsJson(AReason.Path));
  Result.AddPair('inferred', TJSONBool.Create(AReason.Inferred));
end;

function TestJson(const ATest: TAffectedTest): TJSONObject;
var
  mReasons: TJSONArray;
  mReason: TAffectedReason;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ATest.Name);
  Result.AddPair('unit', ATest.UnitName);
  Result.AddPair('fixture', ATest.Fixture);
  Result.AddPair('method', ATest.Method);
  Result.AddPair('run', StringsJson(ATest.RunNames));
  Result.AddPair('uri', TDocumentUris.FromPath(ATest.FileName));
  Result.AddPair('line', TJSONNumber.Create(ATest.Line));
  mReasons := TJSONArray.Create;
  Result.AddPair('reasons', mReasons);
  for mReason in ATest.Reasons do
  begin
    mReasons.AddElement(ReasonJson(mReason));
  end;
end;

function ChangeJson(const AChange: TAffectedChange): TJSONObject;
const
  cKinds: array[TAffectedChangeKind] of string = ('symbol', 'unit');
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', cKinds[AChange.Kind]);
  Result.AddPair('name', AChange.Text);
  Result.AddPair('place', AChange.Place);
  Result.AddPair('uri', TDocumentUris.FromPath(AChange.Source));
end;

function SkippedJson(const ASkipped: TArray<TAffectedSkipped>): TJSONArray;
var
  mSkip: TAffectedSkipped;
  mEntry: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mSkip in ASkipped do
  begin
    mEntry := TJSONObject.Create;
    Result.AddElement(mEntry);
    mEntry.AddPair('uri', TDocumentUris.FromPath(mSkip.FileName));
    mEntry.AddPair('reason', mSkip.Reason);
  end;
end;

function LimitsJson(ALimits: TImpactLimits): TJSONObject;
var
  mLimit: TImpactLimit;
begin
  Result := TJSONObject.Create;
  for mLimit := Low(TImpactLimit) to High(TImpactLimit) do
  begin
    Result.AddPair(TImpactAnalysis.LimitName(mLimit), TJSONBool.Create(mLimit in ALimits));
  end;
end;

class function TAffectedReport.ToJson(const AResult: TAffectedResult): TJSONObject;
var
  mTests, mChanges: TJSONArray;
  mTest: TAffectedTest;
  mChange: TAffectedChange;
begin
  Result := TJSONObject.Create;
  Result.AddPair('base', AResult.Base);
  Result.AddPair('depth', TJSONNumber.Create(AResult.Depth));
  Result.AddPair('all', TJSONBool.Create(AResult.All));
  Result.AddPair('reason', AResult.AllReason);
  if AResult.All then
  begin
    Result.AddPair('run', TJSONArray.Create);
  end
  else
  begin
    Result.AddPair('run', StringsJson(AResult.RunNames));
  end;
  mTests := TJSONArray.Create;
  Result.AddPair('tests', mTests);
  for mTest in AResult.Tests do
  begin
    mTests.AddElement(TestJson(mTest));
  end;
  mChanges := TJSONArray.Create;
  Result.AddPair('changes', mChanges);
  for mChange in AResult.Changes do
  begin
    mChanges.AddElement(ChangeJson(mChange));
  end;
  Result.AddPair('skipped', SkippedJson(AResult.Skipped));
  Result.AddPair('limits', LimitsJson(AResult.Limits));
end;

/// <summary>Werte des Arrays AName in AEntry; nil ohne.</summary>
function StringsIn(AEntry: TJSONObject; const AName: string): TArray<string>;
var
  mArray: TJSONArray;
  mItem: TJSONValue;
begin
  Result := nil;
  if AEntry.TryGetValue<TJSONArray>(AName, mArray) then
  begin
    for mItem in mArray do
    begin
      Result := Result + [mItem.Value];
    end;
  end;
end;

function ReasonOf(AEntry: TJSONObject): TAffectedReason;
begin
  Result := Default(TAffectedReason);
  AEntry.TryGetValue<string>('change', Result.Change);
  AEntry.TryGetValue<Boolean>('inferred', Result.Inferred);
  Result.Path := StringsIn(AEntry, 'path');
end;

function TestOf(AEntry: TJSONObject): TAffectedTest;
var
  mUri: string;
  mReasons: TJSONArray;
  mItem: TJSONValue;
begin
  Result := Default(TAffectedTest);
  AEntry.TryGetValue<string>('name', Result.Name);
  AEntry.TryGetValue<string>('unit', Result.UnitName);
  AEntry.TryGetValue<string>('fixture', Result.Fixture);
  AEntry.TryGetValue<string>('method', Result.Method);
  AEntry.TryGetValue<Integer>('line', Result.Line);
  if AEntry.TryGetValue<string>('uri', mUri) then
  begin
    Result.FileName := TDocumentUris.ToPath(mUri);
  end;
  Result.RunNames := StringsIn(AEntry, 'run');
  if not AEntry.TryGetValue<TJSONArray>('reasons', mReasons) then
  begin
    Exit;
  end;
  for mItem in mReasons do
  begin
    if mItem is TJSONObject then
    begin
      Result.Reasons := Result.Reasons + [ReasonOf(TJSONObject(mItem))];
    end;
  end;
end;

function LimitsOf(ALimits: TJSONObject): TImpactLimits;
var
  mLimit: TImpactLimit;
  mFlag: Boolean;
begin
  Result := [];
  for mLimit := Low(TImpactLimit) to High(TImpactLimit) do
  begin
    if ALimits.TryGetValue<Boolean>(TImpactAnalysis.LimitName(mLimit), mFlag) and mFlag then
    begin
      Include(Result, mLimit);
    end;
  end;
end;

class function TAffectedReport.FromJson(const AValue: TJSONValue): TAffectedResult;
var
  mRoot, mLimits: TJSONObject;
  mArray: TJSONArray;
  mItem: TJSONValue;
begin
  Result := Default(TAffectedResult);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mRoot := TJSONObject(AValue);
  mRoot.TryGetValue<string>('base', Result.Base);
  mRoot.TryGetValue<Integer>('depth', Result.Depth);
  mRoot.TryGetValue<Boolean>('all', Result.All);
  mRoot.TryGetValue<string>('reason', Result.AllReason);
  if mRoot.TryGetValue<TJSONArray>('tests', mArray) then
  begin
    for mItem in mArray do
    begin
      if mItem is TJSONObject then
      begin
        Result.Tests := Result.Tests + [TestOf(TJSONObject(mItem))];
      end;
    end;
  end;
  if mRoot.TryGetValue<TJSONObject>('limits', mLimits) then
  begin
    Result.Limits := LimitsOf(mLimits);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.AffectedTests.Report', cTexts);

end.
