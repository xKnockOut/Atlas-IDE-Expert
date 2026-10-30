unit Atlas.Common.Lsp.Rationale;

// Begründungen (#1123) für Hover und MCP. OfSymbol sammelt die Einträge eines
// Symbols aus dem Index, bei Routinen mit getrennter Implementierung auch die
// aus dem Rumpf (der Index führt Deklaration und Implementierung als zwei
// Symbole). Select wählt nach TRationaleOptions aus: hints.rationale,
// hints.rationaleMarkers und hints.adrFolder; die Marken der TODO-Übersicht
// (#68, Vorgabe TODO und FIXME, Option keywords der Regel todo-comment) fallen
// immer weg, damit eine Marke nur in einer der beiden Listen erscheint. Ausgabe als Markdown, Klartext
// und als Abschnitte "rationale" der strukturierten Doku (#654), je Eintrag
// ein Abschnitt mit der Marke als Name:
//   - ADR-0007 mit passender Datei im ADR-Ordner wird ein Verweis (ref) mit
//     Fundort, den das Plugin in der IDE öffnet; ohne Datei bleibt er Text.
//   - #312 wird ein Link "issue:312"; das Plugin löst ihn über den Tracker
//     der Willkommensseite (#765) auf, ohne Tracker ist er nicht anklickbar.
//   - URLs werden Links.

interface

uses
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rationale.Contract;

type
  /// <summary>Einstellungen für Begründungen in Hover und MCP.</summary>
  TRationaleOptions = record
    /// <summary>hints.rationale: Begründungen in Hover und get_declaration.</summary>
    Enabled: Boolean;
    Markers: TArray<string>;
    /// <summary>Marken der TODO-Übersicht; erscheinen nie als Begründung.</summary>
    Excluded: TArray<string>;
    /// <summary>Ordner der ADR-Dateien als voller Pfad; '' ohne.</summary>
    AdrFolder: string;
    /// <summary>Vorgaben: an, Marken TRationale.DefaultMarkers, ohne TODO und FIXME, kein ADR-Ordner.</summary>
    class function Default: TRationaleOptions; static;
    /// <summary>Aus den Einstellungen eines Arbeitsbereichs mit der Wurzel ARoot ('' ohne).</summary>
    class function FromSettings(const ASettings: TServerSettings; const ARoot: string): TRationaleOptions; static;
  end;

  TLspRationale = class
  public const
    SectionKind = 'rationale';
    /// <summary>Ziel eines Issue-Links: issue:312.</summary>
    IssuePrefix = 'issue:';
  public
    /// <summary>Einträge von ASymbol aus AUnit samt denen der Implementierung bzw. Deklaration derselben
    /// Routine, nach Zeile; ohne Doppelte.</summary>
    class function OfSymbol(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TArray<TRationaleEntry>;
      static;
    /// <summary>Marken laut AHints; ohne Angabe TRationale.DefaultMarkers.</summary>
    class function Markers(const AHints: THintSettings): TArray<string>; static;
    /// <summary>Einträge mit einer Marke aus AOptions.Markers und keiner aus AOptions.Excluded, in Reihenfolge.
    /// </summary>
    class function ByMarkers(const AEntries: TArray<TRationaleEntry>; const AOptions: TRationaleOptions):
      TArray<TRationaleEntry>; static;
    /// <summary>Wie ByMarkers; leer, wenn hints.rationale aus ist (Hover, get_declaration).</summary>
    class function Select(const AEntries: TArray<TRationaleEntry>; const AOptions: TRationaleOptions):
      TArray<TRationaleEntry>; static;
    /// <summary>Ordner der ADR-Dateien: AFolder (hints.adrFolder, '' = TRationale.DefaultAdrFolder) relativ zu
    /// ARoot; absolute Pfade bleiben. '' für einen relativen Ordner ohne ARoot.</summary>
    class function AdrFolder(const AFolder, ARoot: string): string; static;
    /// <summary>Dateien (voller Pfad) im Ordner AFolder; leer, wenn er fehlt oder nicht lesbar ist.</summary>
    class function AdrFiles(const AFolder: string): TArray<string>; static;
    /// <summary>Je Eintrag ein Abschnitt "rationale" an ASections; Verweise auf ADR-Dateien aus AAdrFiles.
    /// </summary>
    class procedure AddSections(ASections: TJSONArray; const AEntries: TArray<TRationaleEntry>;
      const AAdrFiles: TArray<string>); static;
    /// <summary>"**Begründung**" mit je einer Zeile "- **WHY:** Text"; '' ohne Einträge.</summary>
    class function ToMarkdown(const AEntries: TArray<TRationaleEntry>): string; static;
    /// <summary>"Begründung" mit je einer Zeile "WHY: Text"; '' ohne Einträge.</summary>
    class function ToPlainText(const AEntries: TArray<TRationaleEntry>): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rationale.References,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Rules.Builtin.Todos;

{ TRationaleOptions }

class function TRationaleOptions.Default: TRationaleOptions;
begin
  Result.Enabled := True;
  Result.Markers := TRationale.DefaultMarkers;
  Result.Excluded := TTodos.DefaultKeywords;
  Result.AdrFolder := '';
end;

class function TRationaleOptions.FromSettings(const ASettings: TServerSettings;
  const ARoot: string): TRationaleOptions;
begin
  Result.Enabled := ASettings.Hints.Rationale;
  Result.Markers := TLspRationale.Markers(ASettings.Hints);
  Result.Excluded := TTodoRules.Keywords(ASettings);
  Result.AdrFolder := TLspRationale.AdrFolder(ASettings.Hints.AdrFolder, ARoot);
end;

{ TLspRationale }

function SameParamTypes(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for mIndex := 0 to High(A) do
      if not SameText(A[mIndex], B[mIndex]) then
        Exit(False);
end;

function IsRoutine(AKind: TIndexSymbolKind): Boolean;
begin
  Result := AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
end;

class function TLspRationale.OfSymbol(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol):
  TArray<TRationaleEntry>;
var
  mCandidates, mParts: TArray<TIndexSymbol>;
  mOther: TIndexSymbol;
  mEntry, mKnown: TRationaleEntry;
  mFile: string;
  mIndex, mInner: Integer;
  mDuplicate: Boolean;
  mSwap: TRationaleEntry;
begin
  mParts := [ASymbol];
  if IsRoutine(ASymbol.Kind) then
  begin
    // Gegenstück derselben Routine in derselben Datei; bei Überladungen die mit gleichen Parametertypen.
    mFile := AUnit.SymbolFile(ASymbol);
    mCandidates := nil;
    for mOther in AUnit.Symbols do
      if (mOther.Kind = ASymbol.Kind) and SameText(mOther.Name, ASymbol.Name) and
        SameText(mOther.Container, ASymbol.Container) and
        not (mOther.SelectionRange.StartPos = ASymbol.SelectionRange.StartPos) and
        SameText(AUnit.SymbolFile(mOther), mFile) then
        mCandidates := mCandidates + [mOther];
    if Length(mCandidates) = 1 then
      mParts := mParts + mCandidates
    else
      for mOther in mCandidates do
        if SameParamTypes(mOther.ParamTypes, ASymbol.ParamTypes) then
        begin
          mParts := mParts + [mOther];
          Break;
        end;
  end;
  Result := nil;
  for mOther in mParts do
    for mEntry in TRationale.DecodeAll(mOther.Rationale) do
    begin
      mDuplicate := False;
      for mKnown in Result do
        if (mKnown.Line = mEntry.Line) and (mKnown.Marker = mEntry.Marker) then
          mDuplicate := True;
      if not mDuplicate then
        Result := Result + [mEntry];
    end;
  // Nach Zeile; Einfügen hält gleiche Zeilen in ihrer Reihenfolge.
  for mIndex := 1 to High(Result) do
  begin
    mSwap := Result[mIndex];
    mInner := mIndex - 1;
    while (mInner >= 0) and (Result[mInner].Line > mSwap.Line) do
    begin
      Result[mInner + 1] := Result[mInner];
      Dec(mInner);
    end;
    Result[mInner + 1] := mSwap;
  end;
end;

class function TLspRationale.Markers(const AHints: THintSettings): TArray<string>;
begin
  Result := AHints.RationaleMarkers;
  if Length(Result) = 0 then
    Result := TRationale.DefaultMarkers;
end;

class function TLspRationale.ByMarkers(const AEntries: TArray<TRationaleEntry>;
  const AOptions: TRationaleOptions): TArray<TRationaleEntry>;
begin
  Result := TRationale.Filter(AEntries, AOptions.Markers, AOptions.Excluded);
end;

class function TLspRationale.Select(const AEntries: TArray<TRationaleEntry>;
  const AOptions: TRationaleOptions): TArray<TRationaleEntry>;
begin
  Result := nil;
  if AOptions.Enabled then
    Result := ByMarkers(AEntries, AOptions);
end;

class function TLspRationale.AdrFolder(const AFolder, ARoot: string): string;
begin
  Result := Trim(AFolder);
  if Result = '' then
    Result := TRationale.DefaultAdrFolder;
  Result := StringReplace(StringReplace(Result, '/', PathDelim, [rfReplaceAll]), '\', PathDelim, [rfReplaceAll]);
  if TPath.IsPathRooted(Result) then
    Exit;
  if ARoot = '' then
    Exit('');
  Result := ExcludeTrailingPathDelimiter(TPath.Combine(ARoot, Result));
end;

class function TLspRationale.AdrFiles(const AFolder: string): TArray<string>;
var
  mFile: string;
begin
  Result := nil;
  if (AFolder = '') or not TDirectory.Exists(AFolder) then
    Exit;
  try
    for mFile in TDirectory.GetFiles(AFolder) do
      Result := Result + [mFile];
  except
    // Ordner nicht lesbar: Verweise bleiben Text.
    // EInOutError schließt EDirectoryNotFoundException ein.
    on EInOutError do
      Result := nil;
  end;
end;

function TextRun(const AText: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', 'text');
  Result.AddPair('text', AText);
end;

function LinkRun(const ALink: TRationaleLink; const AText: string; const AAdrFiles: TArray<string>): TJSONObject;
var
  mFile: string;
begin
  case ALink.Kind of
    TRationaleLinkKind.Adr:
      begin
        mFile := TRationaleReferences.AdrFile(ALink.Key, AAdrFiles);
        if mFile = '' then
          Exit(TextRun(AText));
        Result := TJSONObject.Create;
        Result.AddPair('kind', 'ref');
        Result.AddPair('text', AText);
        Result.AddPair('target', AText);
        Result.AddPair('name', AText);
        Result.AddPair('file', mFile);
        Result.AddPair('line', TJSONNumber.Create(0));
        Result.AddPair('character', TJSONNumber.Create(0));
      end;
    TRationaleLinkKind.Issue:
      begin
        Result := TJSONObject.Create;
        Result.AddPair('kind', 'link');
        Result.AddPair('text', AText);
        Result.AddPair('target', TLspRationale.IssuePrefix + ALink.Key);
      end;
  else
    Result := TJSONObject.Create;
    Result.AddPair('kind', 'link');
    Result.AddPair('text', AText);
    Result.AddPair('target', ALink.Key);
  end;
end;

class procedure TLspRationale.AddSections(ASections: TJSONArray; const AEntries: TArray<TRationaleEntry>;
  const AAdrFiles: TArray<string>);
var
  mEntry: TRationaleEntry;
  mLink: TRationaleLink;
  mSection: TJSONObject;
  mRuns: TJSONArray;
  mPos: Integer;
begin
  for mEntry in AEntries do
  begin
    mSection := TJSONObject.Create;
    mSection.AddPair('kind', SectionKind);
    mSection.AddPair('name', mEntry.Marker);
    mSection.AddPair('line', TJSONNumber.Create(mEntry.Line));
    mRuns := TJSONArray.Create;
    mPos := 0;
    for mLink in TRationaleReferences.Find(mEntry.Text) do
    begin
      if mLink.Start > mPos then
        mRuns.AddElement(TextRun(Copy(mEntry.Text, mPos + 1, mLink.Start - mPos)));
      mRuns.AddElement(LinkRun(mLink, Copy(mEntry.Text, mLink.Start + 1, mLink.Length), AAdrFiles));
      mPos := mLink.Start + mLink.Length;
    end;
    if mPos < Length(mEntry.Text) then
      mRuns.AddElement(TextRun(Copy(mEntry.Text, mPos + 1, MaxInt)));
    mSection.AddPair('runs', mRuns);
    ASections.AddElement(mSection);
  end;
end;

class function TLspRationale.ToMarkdown(const AEntries: TArray<TRationaleEntry>): string;
var
  mEntry: TRationaleEntry;
begin
  Result := '';
  if Length(AEntries) = 0 then
    Exit;
  Result := '**Begründung**' + #10;
  for mEntry in AEntries do
    Result := Result + #10 + '- **' + mEntry.Marker + ':** ' + mEntry.Text;
end;

class function TLspRationale.ToPlainText(const AEntries: TArray<TRationaleEntry>): string;
var
  mEntry: TRationaleEntry;
begin
  Result := '';
  if Length(AEntries) = 0 then
    Exit;
  Result := 'Begründung';
  for mEntry in AEntries do
    Result := Result + #10 + mEntry.Marker + ': ' + mEntry.Text;
end;

end.
