unit Atlas.Common.Lsp.LeakCandidates;

// Befehl atlas.server.leakCandidates [uri, {report?, classes?}] (#1875):
// Stellen im Projekt hinter uri, die eine geleakte Klasse erzeugen, bewertet
// und sortiert (Atlas.Common.Leaks.Candidates). Die Klassen kommen aus classes
// (Namen) oder aus dem Text eines Leckberichts in report (Meldungsfenster oder
// FastMM-Log, Atlas.Text.LeakReport); Strings und unbekannte Blöcke zählen nicht.
//
// Gesucht wird nur die gemeldete Klasse selbst: Der Bericht nennt die Klasse
// des Objekts zur Laufzeit, „TNachfahre.Create“ erscheint als TNachfahre.
//
// Testunits zählen nur zum Programm, wenn das Projekt selbst ein Testprojekt
// ist; sonst „nicht im Programm“.
//
// Antwort:
//   { project, classes: [{name, count}], hasStacks, truncated,
//     candidates: [{uri, line, character, className, rating, target, routine}] }
// rating wie TLeakCandidates.cRatingNames; line und character 0-basiert.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.LeakReport,
  Atlas.Common.Leaks.Candidates;

type
  /// <summary>Projekt und Dateien für die Suche; die Shell liest geöffnete Dokumente vor der Platte.</summary>
  ILeakCandidateFiles = interface
    ['{4C1E7B52-8D3A-4F6E-9B21-6A0D5E3C7F14}']
    /// <summary>Hauptquelltext und Quelldateien des Projekts hinter AUri; False mit AReason ohne Projekt.</summary>
    function ProjectOf(const AUri: string; out AMainSource: string; out AFiles: TArray<string>;
      out AReason: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
  end;

  TLspLeakCandidates = class
  public const
    cCommand = 'atlas.server.leakCandidates';
    /// <summary>Höchstens so viele Stellen in der Antwort (die dringlichsten).</summary>
    cMaxCandidates = 500;
  private
    FFiles: ILeakCandidateFiles;
    function SourcesOf(const AMainSource: string; const AFileNames, AClassNames: TArray<string>):
      TArray<TLeakSourceFile>;
  public
    constructor Create(const AFiles: ILeakCandidateFiles);
    /// <summary>Klassen aus classes und den Objekten aus report, ohne doppelte Namen.</summary>
    class function ClassesOf(AOptions: TJSONObject; out AHasStacks: Boolean): TArray<TLeakCount>; static;
    /// <summary>Nennt AText einen der Namen? Grobe Vorauswahl vor dem Zerlegen.</summary>
    class function MentionsAny(const AText: string; const AClassNames: TArray<string>): Boolean; static;
    /// <summary>Antwort ohne project. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AClasses: TArray<TLeakCount>; AHasStacks: Boolean;
      const ACandidates: TArray<TLeakCandidate>): TJSONObject; static;
    /// <summary>atlas.server.leakCandidates [uri, {report?, classes?}]; EJsonRpcError ohne Projekt.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  Atlas.Text.Json,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspLeakCandidatesText = (NeedsUri);

const
  cTexts: array[TLspLeakCandidatesText] of TAtlasText = (
    (De: '%s braucht die URI des Projekts'; En: '%s needs the URI of the project'));

{$SCOPEDENUMS OFF}

constructor TLspLeakCandidates.Create(const AFiles: ILeakCandidateFiles);
begin
  inherited Create;
  FFiles := AFiles;
end;

function IndexOfClass(const AClasses: TArray<TLeakCount>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AClasses) do
  begin
    if SameText(AClasses[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function ClassCount(const AName: string; ACount: Integer): TLeakCount;
begin
  Result := Default(TLeakCount);
  Result.Name := AName;
  Result.Kind := TLeakKind.Instance;
  Result.Count := ACount;
end;

class function TLspLeakCandidates.ClassesOf(AOptions: TJSONObject; out AHasStacks: Boolean): TArray<TLeakCount>;
var
  mReport: TLeakReport;
  mCount: TLeakCount;
  mItem: TJSONValue;
  mNames: TJSONArray;
begin
  Result := nil;
  AHasStacks := False;
  mReport := TLeakReports.Parse(TJsonRead.Text(AOptions, 'report'));
  AHasStacks := mReport.HasStacks;
  for mCount in mReport.Counts do
  begin
    if mCount.Kind = TLeakKind.Instance then
    begin
      Result := Result + [mCount];
    end;
  end;
  mNames := TJsonRead.Items(AOptions, 'classes');
  if mNames = nil then
  begin
    Exit;
  end;
  for mItem in mNames do
  begin
    if (mItem is TJSONString) and (Trim(mItem.Value) <> '') and (IndexOfClass(Result, Trim(mItem.Value)) < 0) then
    begin
      Result := Result + [ClassCount(Trim(mItem.Value), 0)];
    end;
  end;
end;

class function TLspLeakCandidates.MentionsAny(const AText: string; const AClassNames: TArray<string>): Boolean;
var
  mLower, mName: string;
begin
  mLower := LowerCase(AText);
  for mName in AClassNames do
  begin
    if Pos(LowerCase(mName), mLower) > 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function IsTestText(const AText: string): Boolean;
begin
  Result := TUsesClauses.UsesTestFramework(TUsesClauses.UsedUnitsOf(AText));
end;

function TLspLeakCandidates.SourcesOf(const AMainSource: string; const AFileNames, AClassNames: TArray<string>):
  TArray<TLeakSourceFile>;
var
  mFileName, mText: string;
  mTestProject: Boolean;
  mSource: TLeakSourceFile;
  mCount: Integer;
begin
  mTestProject := FFiles.ReadText(AMainSource, mText) and IsTestText(mText);
  SetLength(Result, Length(AFileNames));
  mCount := 0;
  for mFileName in AFileNames do
  begin
    if not FFiles.ReadText(mFileName, mText) or not MentionsAny(mText, AClassNames) then
    begin
      Continue;
    end;
    mSource := Default(TLeakSourceFile);
    mSource.FileName := mFileName;
    mSource.Text := mText;
    mSource.InProgram := mTestProject or not IsTestText(mText);
    Result[mCount] := mSource;
    Inc(mCount);
  end;
  SetLength(Result, mCount);
end;

function CandidateToJson(const ACandidate: TLeakCandidate): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', TDocumentUris.FromPath(ACandidate.FileName));
  Result.AddPair('line', TJSONNumber.Create(ACandidate.Position.Line));
  Result.AddPair('character', TJSONNumber.Create(ACandidate.Position.Character));
  Result.AddPair('className', ACandidate.ClassName);
  Result.AddPair('rating', TLeakCandidates.cRatingNames[ACandidate.Rating]);
  Result.AddPair('target', ACandidate.Target);
  Result.AddPair('routine', ACandidate.Routine);
end;

class function TLspLeakCandidates.ToJson(const AClasses: TArray<TLeakCount>; AHasStacks: Boolean;
  const ACandidates: TArray<TLeakCandidate>): TJSONObject;
var
  mClasses, mCandidates: TJSONArray;
  mClass: TJSONObject;
  mCount: TLeakCount;
  mIndex: Integer;
begin
  Result := TJSONObject.Create;
  mClasses := TJSONArray.Create;
  Result.AddPair('classes', mClasses);
  for mCount in AClasses do
  begin
    mClass := TJSONObject.Create;
    mClass.AddPair('name', mCount.Name);
    mClass.AddPair('count', TJSONNumber.Create(mCount.Count));
    mClasses.AddElement(mClass);
  end;
  Result.AddPair('hasStacks', TJSONBool.Create(AHasStacks));
  Result.AddPair('truncated', TJSONBool.Create(Length(ACandidates) > cMaxCandidates));
  mCandidates := TJSONArray.Create;
  Result.AddPair('candidates', mCandidates);
  for mIndex := 0 to High(ACandidates) do
  begin
    if mIndex >= cMaxCandidates then
    begin
      Break;
    end;
    mCandidates.AddElement(CandidateToJson(ACandidates[mIndex]));
  end;
end;

function NamesOf(const AClasses: TArray<TLeakCount>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AClasses));
  for mIndex := 0 to High(AClasses) do
  begin
    Result[mIndex] := AClasses[mIndex].Name;
  end;
end;

function TLspLeakCandidates.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mClasses: TArray<TLeakCount>;
  mHasStacks: Boolean;
  mMainSource, mReason: string;
  mFileNames, mNames: TArray<string>;
  mOptions: TJSONObject;
  mResult: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspLeakCandidatesText.NeedsUri].Fmt([TLspLeakCandidates.cCommand]));
  end;
  if not FFiles.ProjectOf(AArguments.Items[0].Value, mMainSource, mFileNames, mReason) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, mReason);
  end;
  mOptions := nil;
  if (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
  begin
    mOptions := TJSONObject(AArguments.Items[1]);
  end;
  mClasses := ClassesOf(mOptions, mHasStacks);
  mNames := NamesOf(mClasses);
  if Length(mNames) = 0 then
  begin
    mFileNames := nil;
  end;
  mResult := ToJson(mClasses, mHasStacks, TLeakCandidates.Find(SourcesOf(mMainSource, mFileNames, mNames), mNames));
  mResult.AddPair('project', mMainSource);
  Result := mResult;
end;

end.
