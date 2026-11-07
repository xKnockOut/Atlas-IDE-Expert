unit Atlas.Common.Mcp.IndexTools;

// Lesende MCP-Werkzeuge auf dem Symbolindex (#48). Die Ergebnisse sind kurzer
// Text für ein Sprachmodell: Fundstellen mit Datei und Zeile (1-basiert) statt
// ganzer Quelltexte, damit das Modell Dateien nicht vollständig lesen muss.
// Begründungen (// WHY: …, #1123) hängt Declaration als Abschnitt an;
// Rationale listet sie für eine Unit oder ein Symbol (get_rationale).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.Rationale;

type
  TMcpReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Package (.dpk), das die Unit in contains führt; '' ohne.</summary>
  TMcpPackageOf = reference to function(const AUnitName: string): string;
  /// <summary>Einstellungen der Begründungen (#1123) des Arbeitsbereichs.</summary>
  TMcpRationaleOptions = reference to function: TRationaleOptions;

  /// <summary>Eintrag aus RegisterComponents('Seite', [TKlasse, …]).</summary>
  TComponentRegistration = record
    Page: string;
    ClassName: string;
  end;

  TMcpIndexTools = class
  public const
    cMaxResults = 50;
    cMaxDeclarations = 5;
    cMaxDepth = 12;
  private
    FIndex: ISymbolIndex;
    FReadText: TMcpReadText;
    FPackageOf: TMcpPackageOf;
    FRationaleOptions: TMcpRationaleOptions;
    function RationaleOptions: TRationaleOptions;
    function TypeMatches(const AName: string): TArray<TSymbolLocation>;
    procedure AddDescendants(ALines: TStrings; const ATypeName: string; ADepth: Integer;
      AVisited: TDictionary<string, Boolean>);
    function AddSimilar(ALines: TStrings; const AQuery: string): Boolean;
    procedure AddDeclaration(ALines, ASource: TStrings; const ALocation: TSymbolLocation;
      const AOptions: TRationaleOptions);
    function SymbolRationale(const AName: string; const AOptions: TRationaleOptions): string;
    function UnitRationale(const AUnitOrFile: string; const AOptions: TRationaleOptions): string;
    function AncestorLine(const AFound: TSymbolLocation): string;
    function PaletteLine(const AFound: TSymbolLocation): string;
    function PackageLine(const AUnitName: string): string;
    procedure AddMembers(ALines: TStrings; const AClassName: string);
    procedure AddAncestors(ALines: TStrings; const AFound: TSymbolLocation);
  public
    /// <summary>AReadText darf nil sein; dann liefert Declaration nur Fundstellen.</summary>
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TMcpReadText);
    /// <summary>Symbole zu "Bar", "TFoo.Bar" oder "Unit.TFoo.Bar".</summary>
    function Matches(const AName: string): TArray<TSymbolLocation>;
    /// <summary>Symbole nach Name ("Bar" oder "TFoo.Bar"); ohne exakten Treffer Teilstring-Suche.</summary>
    function FindSymbol(const AQuery: string): string;
    /// <summary>Quelltext der Deklaration(en) mit Fundstelle, dazu Begründungen (#1123), wenn hints.rationale an
    /// ist.</summary>
    function Declaration(const AQuery: string): string;
    /// <summary>get_rationale (#1123): Begründungen der Unit AUnitOrFile (Name oder Pfad) samt ihrer Symbole bzw.
    /// des Symbols AName mit Fundstelle; genau eins von beiden ist gesetzt.</summary>
    function Rationale(const AUnitOrFile, AName: string): string;
    /// <summary>Vorfahren (bis zur Wurzel) und Nachfahren (rekursiv) eines Typs.</summary>
    function TypeHierarchy(const ATypeName: string): string;
    /// <summary>uses-Listen und Symbole einer Unit (Name oder Dateipfad).</summary>
    function UnitOutline(const AUnitOrFile: string): string;
    /// <summary>published-Properties mit Typ und Default, Ereignisse mit Signatur, Vorfahren,
    /// Palettenseite und Package einer Komponentenklasse (#113).</summary>
    function ComponentInfo(const AClassName: string): string;
    /// <summary>Alle RegisterComponents-Aufrufe in AText.</summary>
    class function Registrations(const AText: string): TArray<TComponentRegistration>; static;
    /// <summary>Führt die contains-Klausel von ADpkText die Unit AUnitName?</summary>
    class function PackageContains(const ADpkText, AUnitName: string): Boolean; static;
    /// <summary>Für ComponentInfo; ohne Zuweisung ist das Package unbekannt.</summary>
    property PackageOf: TMcpPackageOf read FPackageOf write FPackageOf;
    /// <summary>Ohne Zuweisung gelten TRationaleOptions.Default.</summary>
    property RationaleOptionsFunc: TMcpRationaleOptions read FRationaleOptions write FRationaleOptions;
    /// <summary>Komponentenbaum mit Typen, Ereignissen und Eigenschaften eines Formulars.</summary>
    class function DfmInfo(const AText: string): string; static;
    class function KindName(AKind: TIndexSymbolKind): string; static;
    class function Location(const ALocation: TSymbolLocation): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Lsp.PublishedMembers,
  Atlas.Common.Dfm.FormInfo,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TIndexToolsText = (Enumeration, EnumerationValue, NoSymbolInTheIndex, NoExactMatchSimilarNames, Rationales,
    NoSymbolInTheIndex2, NoRationalesFor, UnitNotInTheIndex, NoRationalesInUnit, GiveExactlyOneOfUnit,
    NoSourcesForInThe, NotInTheIndex, None, NoTypeInTheIndex, NoneInTheIndex, NoteTypesOfThisName, ImplementationOnly,
    MoreMatchesNarrowTheSearch, MoreDeclarationsNarrowTheName, MoreSymbolsNarrowTheName, ClassText, ObjectType,
    Helper, Field, ConstructorText, More, Line, From, None2, Unknown, Events, Signature, Ancestors,
    RegistrationPalettePage, Ancestors2, Descendants, Line2);

const
  cTexts: array[TIndexToolsText] of TAtlasText = (
    (De: 'Aufzählung'; En: 'Enumeration'),
    (De: 'Aufzählungswert'; En: 'Enumeration value'),
    (De: 'Kein Symbol "%s" im Index (%d Units).'; En: 'No symbol "%s" in the index (%d units).'),
    (De: 'Kein exakter Treffer, ähnliche Namen:'; En: 'No exact match, similar names:'),
    (De: 'Begründungen:'; En: 'Rationales:'),
    (De: 'Kein Symbol "%s" im Index.'; En: 'No symbol "%s" in the index.'),
    (De: 'Keine Begründungen zu "%s".'; En: 'No rationales for "%s".'),
    (De: 'Unit "%s" nicht im Index.'; En: 'Unit "%s" not in the index.'),
    (De: 'Keine Begründungen in Unit %s.'; En: 'No rationales in unit %s.'),
    (De: 'Genau eins von "unit" und "name" angeben.'; En: 'Give exactly one of "unit" and "name".'),
    (De: 'Keine Quellen zu "%s" im Index; nur der Name ist bekannt (z. B. nur als .dcu vorhanden).';
     En: 'No sources for "%s" in the index; only the name is known (e.g. only available as .dcu).'),
    (De: '  - %s (nicht im Index)'; En: '  - %s (not in the index)'),
    (De: '  (keine)'; En: '  (none)'),
    (De: 'Kein Typ "%s" im Index.'; En: 'No type "%s" in the index.'),
    (De: '  (keine im Index)'; En: '  (none in the index)'),
    (De: 'Hinweis: %d Typen dieses Namens, gezeigt wird der erste.';
     En: 'Note: %d types of this name, the first one is shown.'),
    (De: ', nur implementation'; En: ', implementation only'),
    (De: '… weitere Treffer, Suche genauer fassen'; En: '… more matches, narrow the search'),
    (De: '… weitere Deklarationen, Namen genauer fassen (TFoo.Bar)';
     En: '… more declarations, narrow the name (TFoo.Bar)'),
    (De: '… weitere Symbole, Namen genauer fassen (TFoo.Bar)'; En: '… more symbols, narrow the name (TFoo.Bar)'),
    (De: 'Klasse'; En: 'Class'),
    (De: 'Objekttyp'; En: 'Object type'),
    (De: 'Helfer'; En: 'Helper'),
    (De: 'Feld'; En: 'Field'),
    (De: 'Konstruktor'; En: 'Constructor'),
    (De: '… %d weitere'; En: '… %d more'),
    (De: '- %s (Zeile %d): %s'; En: '- %s (line %d): %s'),
    (De: ' (aus %s)'; En: ' (from %s)'),
    (De: 'keine'; En: 'none'),
    (De: 'unbekannt'; En: 'unknown'),
    (De: 'Ereignisse:'; En: 'Events:'),
    (De: ' – Signatur '; En: ' – signature '),
    (De: 'Vorfahren: '; En: 'Ancestors: '),
    (De: 'Registrierung (Palettenseite): '; En: 'Registration (palette page): '),
    (De: 'Vorfahren:'; En: 'Ancestors:'),
    (De: 'Nachfahren:'; En: 'Descendants:'),
    (De: '%s%s %s%s – Zeile %d'; En: '%s%s %s%s – line %d'));

{$SCOPEDENUMS OFF}

const
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];

function JoinLines(ALines: TStrings): string;
begin
  Result := TrimRight(ALines.Text);
end;

{ TMcpIndexTools }

constructor TMcpIndexTools.Create(const AIndex: ISymbolIndex; const AReadText: TMcpReadText);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
end;

class function TMcpIndexTools.KindName(AKind: TIndexSymbolKind): string;
begin
  case AKind of
    TIndexSymbolKind.ClassType: Result := cTexts[TIndexToolsText.ClassText].Text;
    TIndexSymbolKind.ObjectType: Result := cTexts[TIndexToolsText.ObjectType].Text;
    TIndexSymbolKind.RecordType: Result := 'Record';
    TIndexSymbolKind.InterfaceType: Result := 'Interface';
    TIndexSymbolKind.HelperType: Result := cTexts[TIndexToolsText.Helper].Text;
    TIndexSymbolKind.EnumType: Result := cTexts[TIndexToolsText.Enumeration].Text;
    TIndexSymbolKind.TypeAlias: Result := 'Typ';
    TIndexSymbolKind.EnumMember: Result := cTexts[TIndexToolsText.EnumerationValue].Text;
    TIndexSymbolKind.Constant: Result := 'Konstante';
    TIndexSymbolKind.Variable: Result := 'Variable';
    TIndexSymbolKind.Field: Result := cTexts[TIndexToolsText.Field].Text;
    TIndexSymbolKind.Property_: Result := 'Property';
    TIndexSymbolKind.Method: Result := 'Methode';
    TIndexSymbolKind.Constructor_: Result := cTexts[TIndexToolsText.ConstructorText].Text;
  else
    Result := 'Routine';
  end;
end;

class function TMcpIndexTools.Location(const ALocation: TSymbolLocation): string;
begin
  Result := Format('%s:%d', [ALocation.FileName, ALocation.Symbol.SelectionRange.StartPos.Line + 1]);
end;

function Describe(const ALocation: TSymbolLocation): string;
begin
  Result := Format('%s (%s', [ALocation.Symbol.QualifiedName, TMcpIndexTools.KindName(ALocation.Symbol.Kind)]);
  if ALocation.Symbol.TypeName <> '' then
  begin
    Result := Result + ': ' + ALocation.Symbol.TypeName;
  end;
  if not ALocation.Symbol.InInterface then
  begin
    Result := Result + cTexts[TIndexToolsText.ImplementationOnly].Text;
  end;
  Result := Result + Format(') – Unit %s, %s', [ALocation.UnitName, TMcpIndexTools.Location(ALocation)]);
end;

function TMcpIndexTools.Matches(const AName: string): TArray<TSymbolLocation>;
var
  mQuery, mContainer, mName: string;
  mDot: Integer;
  mFound: TList<TSymbolLocation>;
  mLocation: TSymbolLocation;
begin
  mQuery := Trim(AName);
  mName := mQuery;
  mContainer := '';
  mDot := LastDelimiter('.', mName);
  if mDot > 0 then
  begin
    mContainer := Copy(mName, 1, mDot - 1);
    // Unit-Präfix (System.SysUtils.TFoo.Bar) zählt nicht zum Container.
    if LastDelimiter('.', mContainer) > 0 then
    begin
      mContainer := Copy(mContainer, LastDelimiter('.', mContainer) + 1, MaxInt);
    end;
    mName := Copy(mName, mDot + 1, MaxInt);
  end;
  mFound := TList<TSymbolLocation>.Create;
  try
    for mLocation in FIndex.FindSymbols(mName) do
    begin
      if (mContainer = '') or SameText(mLocation.Symbol.Container, mContainer) or
        ((mDot > 0) and SameText(mLocation.UnitName, Copy(mQuery, 1, mDot - 1))) then
      begin
        mFound.Add(mLocation);
      end;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

function TMcpIndexTools.TypeMatches(const AName: string): TArray<TSymbolLocation>;
var
  mLocation: TSymbolLocation;
  mFound: TList<TSymbolLocation>;
begin
  mFound := TList<TSymbolLocation>.Create;
  try
    for mLocation in Matches(AName) do
    begin
      if mLocation.Symbol.Kind in cTypeKinds then
      begin
        mFound.Add(mLocation);
      end;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

/// <summary>Die exakten Treffer AFound, höchstens MaxResults.</summary>
procedure AddExact(ALines: TStrings; const AFound: TArray<TSymbolLocation>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AFound) do
  begin
    if mIndex >= TMcpIndexTools.cMaxResults then
    begin
      ALines.Add(cTexts[TIndexToolsText.More].Fmt([Length(AFound) - mIndex]));
      Break;
    end;
    ALines.Add(Describe(AFound[mIndex]));
  end;
end;

function TMcpIndexTools.AddSimilar(ALines: TStrings; const AQuery: string): Boolean;
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  // Kein exakter Treffer: Teilstring im Namen, z. B. "Customer" findet TCustomerList.
  for mUnit in FIndex.Units do
  begin
    for mSymbol in mUnit.Symbols do
    begin
      if not ContainsText(mSymbol.Name, AQuery) then
      begin
        Continue;
      end;
      if ALines.Count >= cMaxResults then
      begin
        ALines.Add(cTexts[TIndexToolsText.MoreMatchesNarrowTheSearch].Text);
        Exit(False);
      end;
      mLocation.UnitName := mUnit.UnitName;
      mLocation.FileName := mUnit.FileName;
      mLocation.Symbol := mSymbol;
      ALines.Add(Describe(mLocation));
    end;
  end;
  Result := True;
end;

function TMcpIndexTools.FindSymbol(const AQuery: string): string;
var
  mLines: TStringList;
  mFound: TArray<TSymbolLocation>;
begin
  mLines := TStringList.Create;
  try
    mFound := Matches(AQuery);
    if Length(mFound) > 0 then
    begin
      AddExact(mLines, mFound);
      Result := JoinLines(mLines);
    end
    else if not AddSimilar(mLines, AQuery) then
    begin
      Result := JoinLines(mLines);
    end
    else if mLines.Count = 0 then
    begin
      Result := cTexts[TIndexToolsText.NoSymbolInTheIndex].Fmt([AQuery, FIndex.UnitCount]);
    end
    else
    begin
      Result := cTexts[TIndexToolsText.NoExactMatchSimilarNames].Text + sLineBreak + JoinLines(mLines);
    end;
  finally
    mLines.Free;
  end;
end;

function TMcpIndexTools.RationaleOptions: TRationaleOptions;
begin
  if Assigned(FRationaleOptions) then
  begin
    Result := FRationaleOptions();
  end
  else
  begin
    Result := TRationaleOptions.Default;
  end;
end;

/// <summary>"- WHY (Zeile 12): Text" je Eintrag (Zeilen ab 1).</summary>
procedure AddEntries(ALines: TStrings; const AEntries: TArray<TRationaleEntry>);
var
  mEntry: TRationaleEntry;
begin
  for mEntry in AEntries do
  begin
    ALines.Add(cTexts[TIndexToolsText.Line].Fmt([mEntry.Marker, mEntry.Line + 1, mEntry.Text]));
  end;
end;

/// <summary>Begründungen des Symbols an ALocation samt Implementierung bzw. Deklaration; leer ohne Unit.</summary>
function EntriesOf(const AIndex: ISymbolIndex; const ALocation: TSymbolLocation): TArray<TRationaleEntry>;
var
  mUnit: TUnitIndex;
begin
  Result := nil;
  if AIndex.FindUnit(ALocation.UnitName, mUnit) then
  begin
    Result := TLspRationale.OfSymbol(mUnit, ALocation.Symbol);
  end;
end;

procedure TMcpIndexTools.AddDeclaration(ALines, ASource: TStrings; const ALocation: TSymbolLocation;
  const AOptions: TRationaleOptions);
var
  mText: string;
  mLine: Integer;
  mEntries: TArray<TRationaleEntry>;
begin
  if ALines.Count > 0 then
  begin
    ALines.Add('');
  end;
  ALines.Add('// ' + Describe(ALocation));
  if Assigned(FReadText) and FReadText(ALocation.FileName, mText) then
  begin
    ASource.Text := mText;
    for mLine := Max(ALocation.Symbol.Range.StartPos.Line, 0) to Min(ALocation.Symbol.Range.EndPos.Line,
      ASource.Count - 1) do
    begin
      ALines.Add(ASource[mLine]);
    end;
  end;
  // Begründungen (#1123): über der Deklaration und im Rumpf der Implementierung.
  mEntries := TLspRationale.Select(EntriesOf(FIndex, ALocation), AOptions);
  if Length(mEntries) > 0 then
  begin
    ALines.Add(cTexts[TIndexToolsText.Rationales].Text);
    AddEntries(ALines, mEntries);
  end;
end;

function TMcpIndexTools.Declaration(const AQuery: string): string;
var
  mLines, mSource: TStringList;
  mLocation: TSymbolLocation;
  mCount: Integer;
  mOptions: TRationaleOptions;
begin
  mOptions := RationaleOptions;
  mLines := TStringList.Create;
  mSource := TStringList.Create;
  try
    mCount := 0;
    for mLocation in Matches(AQuery) do
    begin
      if mCount >= cMaxDeclarations then
      begin
        mLines.Add(cTexts[TIndexToolsText.MoreDeclarationsNarrowTheName].Text);
        Break;
      end;
      Inc(mCount);
      AddDeclaration(mLines, mSource, mLocation, mOptions);
    end;
    if mCount = 0 then
    begin
      Exit(cTexts[TIndexToolsText.NoSymbolInTheIndex2].Fmt([AQuery]));
    end;
    Result := JoinLines(mLines);
  finally
    mSource.Free;
    mLines.Free;
  end;
end;

function TMcpIndexTools.SymbolRationale(const AName: string; const AOptions: TRationaleOptions): string;
var
  mLines: TStringList;
  mLocation: TSymbolLocation;
  mEntries: TArray<TRationaleEntry>;
  mCount: Integer;
begin
  mLines := TStringList.Create;
  try
    mCount := 0;
    for mLocation in Matches(AName) do
    begin
      mEntries := TLspRationale.ByMarkers(EntriesOf(FIndex, mLocation), AOptions);
      if Length(mEntries) = 0 then
      begin
        Continue;
      end;
      if mCount >= cMaxDeclarations then
      begin
        mLines.Add(cTexts[TIndexToolsText.MoreSymbolsNarrowTheName].Text);
        Break;
      end;
      Inc(mCount);
      if mLines.Count > 0 then
      begin
        mLines.Add('');
      end;
      mLines.Add(Describe(mLocation));
      AddEntries(mLines, mEntries);
    end;
    Result := JoinLines(mLines);
    if mCount = 0 then
    begin
      Result := cTexts[TIndexToolsText.NoRationalesFor].Fmt([AName]);
    end;
  finally
    mLines.Free;
  end;
end;

/// <summary>Begründungen der Unit selbst und je Symbol nur die eigenen Einträge: Deklaration und Implementierung
/// stehen mit ihrer Fundstelle getrennt. Liefert die Zahl der Einträge.</summary>
function AddUnitEntries(ALines: TStrings; const AUnit: TUnitIndex; const AOptions: TRationaleOptions): Integer;
var
  mEntries: TArray<TRationaleEntry>;
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  Result := 0;
  mEntries := TLspRationale.ByMarkers(TRationale.DecodeAll(AUnit.Rationale), AOptions);
  if Length(mEntries) > 0 then
  begin
    ALines.Add('Unit:');
    AddEntries(ALines, mEntries);
    Inc(Result, Length(mEntries));
  end;
  for mSymbol in AUnit.Symbols do
  begin
    mEntries := TLspRationale.ByMarkers(TRationale.DecodeAll(mSymbol.Rationale), AOptions);
    if Length(mEntries) > 0 then
    begin
      mLocation.UnitName := AUnit.UnitName;
      mLocation.FileName := AUnit.SymbolFile(mSymbol);
      mLocation.Symbol := mSymbol;
      ALines.Add(Describe(mLocation));
      AddEntries(ALines, mEntries);
      Inc(Result, Length(mEntries));
    end;
  end;
end;

function TMcpIndexTools.UnitRationale(const AUnitOrFile: string; const AOptions: TRationaleOptions): string;
var
  mLines: TStringList;
  mUnit: TUnitIndex;
begin
  if not FIndex.FindUnit(AUnitOrFile, mUnit) and not FIndex.FindFile(AUnitOrFile, mUnit) then
  begin
    Exit(cTexts[TIndexToolsText.UnitNotInTheIndex].Fmt([AUnitOrFile]));
  end;
  mLines := TStringList.Create;
  try
    mLines.Add(Format('unit %s – %s', [mUnit.UnitName, mUnit.FileName]));
    if AddUnitEntries(mLines, mUnit, AOptions) = 0 then
    begin
      Result := cTexts[TIndexToolsText.NoRationalesInUnit].Fmt([mUnit.UnitName]);
    end
    else
    begin
      Result := JoinLines(mLines);
    end;
  finally
    mLines.Free;
  end;
end;

function TMcpIndexTools.Rationale(const AUnitOrFile, AName: string): string;
begin
  // get_rationale ist über mcp.disabledTools abschaltbar; hints.rationale gilt für Hover und get_declaration.
  if (Trim(AUnitOrFile) = '') = (Trim(AName) = '') then
  begin
    Result := cTexts[TIndexToolsText.GiveExactlyOneOfUnit].Text;
  end
  else if Trim(AName) <> '' then
  begin
    Result := SymbolRationale(AName, RationaleOptions);
  end
  else
  begin
    Result := UnitRationale(AUnitOrFile, RationaleOptions);
  end;
end;

procedure TMcpIndexTools.AddDescendants(ALines: TStrings; const ATypeName: string; ADepth: Integer;
  AVisited: TDictionary<string, Boolean>);
var
  mLocation: TSymbolLocation;
  mKey: string;
begin
  if ADepth > cMaxDepth then
  begin
    Exit;
  end;
  for mLocation in FIndex.Descendants(ATypeName) do
  begin
    mKey := LowerCase(mLocation.UnitName + '.' + mLocation.Symbol.QualifiedName);
    if AVisited.ContainsKey(mKey) then
    begin
      Continue;
    end;
    AVisited.Add(mKey, True);
    ALines.Add(StringOfChar(' ', ADepth * 2) + '- ' + Describe(mLocation));
    AddDescendants(ALines, mLocation.Symbol.Name, ADepth + 1, AVisited);
  end;
end;

class function TMcpIndexTools.Registrations(const AText: string): TArray<TComponentRegistration>;
const
  cCall = 'registercomponents';
var
  mLower, mPage, mName: string;
  mStart, mIndex, mClose: Integer;
  mEntry: TComponentRegistration;
begin
  Result := nil;
  mLower := LowerCase(AText);
  mStart := Pos(cCall, mLower);
  while mStart > 0 do
  begin
    // RegisterComponents('Seite', [TA, TB]);
    mIndex := PosEx('''', AText, mStart + Length(cCall));
    mClose := PosEx('''', AText, mIndex + 1);
    if (mIndex = 0) or (mClose = 0) then
    begin
      Break;
    end;
    mPage := Copy(AText, mIndex + 1, mClose - mIndex - 1);
    mIndex := PosEx('[', AText, mClose);
    mClose := PosEx(']', AText, mIndex + 1);
    if (mIndex = 0) or (mClose = 0) then
    begin
      Break;
    end;
    for mName in Copy(AText, mIndex + 1, mClose - mIndex - 1).Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        mEntry.Page := mPage;
        mEntry.ClassName := Trim(mName);
        Result := Result + [mEntry];
      end;
    end;
    mStart := PosEx(cCall, mLower, mClose);
  end;
end;

class function TMcpIndexTools.PackageContains(const ADpkText, AUnitName: string): Boolean;
var
  mLower, mName: string;
  mStart, mStop: Integer;
  mEntry: string;
begin
  Result := False;
  mLower := LowerCase(ADpkText);
  mStart := Pos('contains', mLower);
  while (mStart > 0) and (((mStart > 1) and CharInSet(mLower[mStart - 1], ['a'..'z', '0'..'9', '_', '.'])) or
    ((mStart + 8 <= Length(mLower)) and CharInSet(mLower[mStart + 8], ['a'..'z', '0'..'9', '_']))) do
  begin
    mStart := PosEx('contains', mLower, mStart + 1);
  end;
  if mStart = 0 then
  begin
    Exit;
  end;
  mStop := PosEx(';', mLower, mStart);
  if mStop = 0 then
  begin
    mStop := Length(mLower) + 1;
  end;
  mName := LowerCase(AUnitName);
  // Einträge: "Unit" oder "Unit in 'Pfad'", durch Kommas getrennt.
  for mEntry in Copy(mLower, mStart + 8, mStop - mStart - 8).Split([',']) do
  begin
    if SameText(Trim(Copy(Trim(mEntry), 1, Pos(' ', Trim(mEntry) + ' ') - 1)), mName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>" (aus TBasis)", wenn AMember nicht in AClassName selbst deklariert ist.</summary>
function InheritedNote(const AMember: TPublishedMember; const AClassName: string): string;
begin
  Result := '';
  if not SameText(AMember.DeclaringClass, AClassName) then
  begin
    Result := cTexts[TIndexToolsText.From].Fmt([AMember.DeclaringClass]);
  end;
end;

function TMcpIndexTools.AncestorLine(const AFound: TSymbolLocation): string;
var
  mCurrent: TSymbolLocation;
  mParents: TArray<TSymbolLocation>;
  mChain: TList<string>;
begin
  // Vorfahrenkette über die jeweils erste Basisklasse.
  Result := AFound.Symbol.Name;
  mCurrent := AFound;
  mChain := TList<string>.Create;
  try
    while (Length(mCurrent.Symbol.Ancestors) > 0) and (mChain.Count < cMaxDepth) and
      not mChain.Contains(LowerCase(mCurrent.Symbol.Ancestors[0])) do
    begin
      mChain.Add(LowerCase(mCurrent.Symbol.Ancestors[0]));
      Result := Result + ' → ' + mCurrent.Symbol.Ancestors[0];
      mParents := TypeMatches(mCurrent.Symbol.Ancestors[0]);
      if Length(mParents) = 0 then
      begin
        Break;
      end;
      mCurrent := mParents[0];
    end;
  finally
    mChain.Free;
  end;
end;

/// <summary>Palettenseiten von AClassName aus den RegisterComponents-Aufrufen in AText, an APages angehängt.
/// </summary>
procedure AddPages(var APages: string; const AText, AClassName: string);
var
  mRegistration: TComponentRegistration;
begin
  for mRegistration in TMcpIndexTools.Registrations(AText) do
  begin
    if SameText(mRegistration.ClassName, AClassName) and (Pos(mRegistration.Page, APages) = 0) then
    begin
      if APages <> '' then
      begin
        APages := APages + ', ';
      end;
      APages := APages + mRegistration.Page;
    end;
  end;
end;

function TMcpIndexTools.PaletteLine(const AFound: TSymbolLocation): string;
var
  mFiles: TList<string>;
  mRoutine: TSymbolLocation;
  mFileName, mText: string;
begin
  // Palettenseite: RegisterComponents in der Unit der Klasse und in allen Register-Routinen.
  Result := '';
  mFiles := TList<string>.Create;
  try
    mFiles.Add(AFound.FileName);
    for mRoutine in FIndex.FindSymbols('Register') do
    begin
      if (mRoutine.Symbol.Container = '') and not mFiles.Contains(mRoutine.FileName) then
      begin
        mFiles.Add(mRoutine.FileName);
      end;
    end;
    for mFileName in mFiles do
    begin
      if Assigned(FReadText) and FReadText(mFileName, mText) then
      begin
        AddPages(Result, mText, AFound.Symbol.Name);
      end;
    end;
  finally
    mFiles.Free;
  end;
  if Result = '' then
  begin
    Result := cTexts[TIndexToolsText.None2].Text;
  end;
end;

function TMcpIndexTools.PackageLine(const AUnitName: string): string;
begin
  Result := '';
  if Assigned(FPackageOf) then
  begin
    Result := FPackageOf(AUnitName);
  end;
  if Result = '' then
  begin
    Result := cTexts[TIndexToolsText.Unknown].Text;
  end;
end;

procedure TMcpIndexTools.AddMembers(ALines: TStrings; const AClassName: string);
var
  mReadText: TMemberReadText;
  mMembers: TArray<TPublishedMember>;
  mMember: TPublishedMember;
  mLine, mTail: string;
begin
  mReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FReadText(AFileName, AText);
    end;
  mMembers := TPublishedMembers.Collect(FIndex, AClassName, mReadText);
  ALines.Add('Properties:');
  for mMember in mMembers do
  begin
    if not mMember.IsEvent then
    begin
      mLine := Format('  %s: %s', [mMember.Name, mMember.TypeName]);
      if TPublishedMembers.DefaultText(mMember) <> '' then
      begin
        mLine := mLine + ' ' + TPublishedMembers.DefaultText(mMember);
      end;
      ALines.Add(mLine + InheritedNote(mMember, AClassName));
    end;
  end;
  ALines.Add(cTexts[TIndexToolsText.Events].Text);
  for mMember in mMembers do
  begin
    if mMember.IsEvent then
    begin
      mLine := Format('  %s: %s', [mMember.Name, mMember.TypeName]);
      if TPublishedMembers.EventTail(FIndex, mReadText, AClassName, mMember.Name, mTail) then
      begin
        mLine := mLine + cTexts[TIndexToolsText.Signature].Text + mTail;
      end;
      ALines.Add(mLine + InheritedNote(mMember, AClassName));
    end;
  end;
end;

function TMcpIndexTools.ComponentInfo(const AClassName: string): string;
var
  mLines: TStringList;
  mFound: TArray<TSymbolLocation>;
begin
  mFound := TypeMatches(AClassName);
  if Length(mFound) = 0 then
  begin
    Exit(cTexts[TIndexToolsText.NoSourcesForInThe].Fmt([AClassName]));
  end;
  mLines := TStringList.Create;
  try
    mLines.Add(Describe(mFound[0]));
    mLines.Add(cTexts[TIndexToolsText.Ancestors].Text + AncestorLine(mFound[0]));
    mLines.Add(cTexts[TIndexToolsText.RegistrationPalettePage].Text + PaletteLine(mFound[0]));
    mLines.Add('Package: ' + PackageLine(mFound[0].UnitName));
    if Assigned(FReadText) then
    begin
      AddMembers(mLines, mFound[0].Symbol.Name);
    end;
    Result := JoinLines(mLines);
  finally
    mLines.Free;
  end;
end;

procedure TMcpIndexTools.AddAncestors(ALines: TStrings; const AFound: TSymbolLocation);
var
  mCurrent: TSymbolLocation;
  mParents: TArray<TSymbolLocation>;
  mChain: TList<string>;
  mName: string;
begin
  // Vorfahren über den jeweils ersten Eintrag (Basisklasse bzw. -interface).
  ALines.Add(cTexts[TIndexToolsText.Ancestors2].Text);
  mCurrent := AFound;
  mChain := TList<string>.Create;
  try
    while (Length(mCurrent.Symbol.Ancestors) > 0) and (mChain.Count < cMaxDepth) do
    begin
      mName := mCurrent.Symbol.Ancestors[0];
      if mChain.Contains(LowerCase(mName)) then
      begin
        Break;
      end;
      mChain.Add(LowerCase(mName));
      mParents := TypeMatches(mName);
      if Length(mParents) = 0 then
      begin
        ALines.Add(cTexts[TIndexToolsText.NotInTheIndex].Fmt([mName]));
        Break;
      end;
      mCurrent := mParents[0];
      ALines.Add('  - ' + Describe(mCurrent));
    end;
    if mChain.Count = 0 then
    begin
      ALines.Add(cTexts[TIndexToolsText.None].Text);
    end;
  finally
    mChain.Free;
  end;
end;

function TMcpIndexTools.TypeHierarchy(const ATypeName: string): string;
var
  mLines: TStringList;
  mFound: TArray<TSymbolLocation>;
  mVisited: TDictionary<string, Boolean>;
  mIndex: Integer;
begin
  mFound := TypeMatches(ATypeName);
  if Length(mFound) = 0 then
  begin
    Exit(cTexts[TIndexToolsText.NoTypeInTheIndex].Fmt([ATypeName]));
  end;
  mLines := TStringList.Create;
  mVisited := TDictionary<string, Boolean>.Create;
  try
    mLines.Add(Describe(mFound[0]));
    if Length(mFound[0].Symbol.Ancestors) > 1 then
    begin
      mLines.Add('Implementiert/erweitert: ' + string.Join(', ', Copy(mFound[0].Symbol.Ancestors, 1, MaxInt)));
    end;
    AddAncestors(mLines, mFound[0]);
    mLines.Add(cTexts[TIndexToolsText.Descendants].Text);
    mIndex := mLines.Count;
    AddDescendants(mLines, mFound[0].Symbol.Name, 1, mVisited);
    if mLines.Count = mIndex then
    begin
      mLines.Add(cTexts[TIndexToolsText.NoneInTheIndex].Text);
    end;
    if Length(mFound) > 1 then
    begin
      mLines.Add(cTexts[TIndexToolsText.NoteTypesOfThisName].Fmt([Length(mFound)]));
    end;
    Result := JoinLines(mLines);
  finally
    mVisited.Free;
    mLines.Free;
  end;
end;

function TMcpIndexTools.UnitOutline(const AUnitOrFile: string): string;
var
  mUnitIndex: TUnitIndex;
  mLines: TStringList;
  mSymbol: TIndexSymbol;
  mIndent, mSection: string;
  mInInterface: Boolean;
begin
  if not FIndex.FindUnit(AUnitOrFile, mUnitIndex) and not FIndex.FindFile(AUnitOrFile, mUnitIndex) then
  begin
    Exit(cTexts[TIndexToolsText.UnitNotInTheIndex].Fmt([AUnitOrFile]));
  end;
  mLines := TStringList.Create;
  try
    mLines.Add(Format('unit %s – %s', [mUnitIndex.UnitName, mUnitIndex.FileName]));
    if Length(mUnitIndex.InterfaceUses) > 0 then
    begin
      mLines.Add('uses (interface): ' + string.Join(', ', mUnitIndex.InterfaceUses));
    end;
    if Length(mUnitIndex.ImplementationUses) > 0 then
    begin
      mLines.Add('uses (implementation): ' + string.Join(', ', mUnitIndex.ImplementationUses));
    end;
    mInInterface := False;
    mSection := '';
    for mSymbol in mUnitIndex.Symbols do
    begin
      if (mSection = '') or (mSymbol.InInterface <> mInInterface) then
      begin
        mInInterface := mSymbol.InInterface;
        mSection := IfThen(mInInterface, 'interface', 'implementation');
        mLines.Add(mSection + ':');
      end;
      mIndent := IfThen(mSymbol.Container = '', '  ', '    ');
      mLines.Add(cTexts[TIndexToolsText.Line2].Fmt([mIndent, KindName(mSymbol.Kind),
        IfThen(mSymbol.Container = '', mSymbol.Name, mSymbol.QualifiedName),
        IfThen(mSymbol.TypeName <> '', ': ' + mSymbol.TypeName, '') +
        IfThen(Length(mSymbol.Ancestors) > 0, '(' + string.Join(', ', mSymbol.Ancestors) + ')', ''),
        mSymbol.SelectionRange.StartPos.Line + 1]));
    end;
    Result := JoinLines(mLines);
  finally
    mLines.Free;
  end;
end;

class function TMcpIndexTools.DfmInfo(const AText: string): string;
begin
  // Gemeinsam mit dem Hover über Formularfelder (#126).
  Result := TFormInfo.Describe(AText);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.IndexTools', cTexts);

end.
