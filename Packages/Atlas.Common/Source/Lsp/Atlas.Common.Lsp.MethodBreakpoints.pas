unit Atlas.Common.Lsp.MethodBreakpoints;

// Haltepunkte auf Methoden nach Name oder Muster (#855), Teil des Servers: Welche Methoden passen zu einem Muster und
// an welcher Zeile steht jeweils ihr erster ausführbarer Befehl. Das Plugin zeigt die Treffer als Vorschau und legt
// die Haltepunkte als Gruppe an; beim Mitwachsen fragt es vor dem Debug-Start erneut.
//
// Befehl atlas.server.methodBreakpoints, Argumente [{"pattern": "*.Validiere*", "overrides": true,
// "overloads": true}]. Antwort:
//   {"format": 1, "pattern": "*.Validiere*", "truncated": false, "hits": [{"uri": "file:///…/Kunden.pas",
//    "unit": "Kunden", "container": "TKunde", "name": "Validiere", "signature": "procedure Validiere;",
//    "declarationLine": 12, "headerLine": 40, "line": 42, "source": true, "reason": "match", "via": ""}]}
//   Zeilen ab 0; "line" ist -1, wenn der Rumpf nicht gefunden wurde ("source": false, im Fenster ausgegraut).
//   "reason": "match" (passt selbst), "override" (überschreibt einen Treffer, "via" nennt ihn), "implementation"
//   (setzt einen Interface-Member um, "via" nennt ihn). Bei einem ungültigen Muster {"format": 1, "error": "…"}.
//
// Muster (ohne Groß-/Kleinschreibung, Platzhalter * und ?):
//   TKunde.Speichere   Methode einer Klasse (auch geschachtelt: TAussen.TInnen.Speichere oder nur TInnen)
//   TKunde.*           alle Methoden der Klasse
//   *.Validiere*       alle Methoden und Routinen, deren Name passt
//   Kunde.Import.*     alle Routinen der Unit (der Teil vor dem letzten Punkt ist ein Unit-Name im Index)
//   Kunde.Import.TKunde.Speichere   Klasse in einer bestimmten Unit
//   IAuftrag.Pruefe    alle Klassen, die den Interface-Member umsetzen (auch über Methodenzuordnungen)
//   TKunde.Speichere(Integer, string)   nur die Überladung mit diesen Parametertypen
// Bibliotheks-Units (RTL, VCL) werden nur durchsucht, wenn der Teil vor dem Namen keinen Platzhalter enthält.
//
// Schalter: "overrides" nimmt zu virtuellen Treffern die Überschreibungen in den Nachfahren dazu; aus, fallen
// override-Methoden ganz weg. "overloads" aus lässt je Klasse und Name nur die erste Deklaration stehen, wenn das
// Muster keine Parameterliste nennt. Abstrakte und externe Routinen haben keinen Rumpf und erscheinen nicht.
//
// Erster ausführbarer Befehl: die erste Anweisung im Rumpf, in begin…end, try und Marken hinein; Inline-Variablen
// nur mit Wert. Ein leerer Rumpf bekommt die Zeile seines end, asm-Blöcke die Zeile nach asm.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Zerlegtes Muster; Parse prüft und ordnet den Teil vor dem Namen einer Unit oder einem Typ zu.</summary>
  TMethodPattern = record
    Text: string;
    /// <summary>Exakter Unit-Name; '' = jede Unit.</summary>
    UnitName: string;
    /// <summary>Muster für den umgebenden Typ ohne Typargumente; '*' = jeder, auch freie Routinen.</summary>
    ContainerMask: string;
    NameMask: string;
    /// <summary>Das Muster nennt eine Parameterliste; dann zählen nur Überladungen mit genau diesen Typen.</summary>
    HasParams: Boolean;
    ParamTypes: TArray<string>;
    /// <summary>Der Teil vor dem Namen hat keinen Platzhalter: auch Bibliotheks-Units durchsuchen.</summary>
    Exact: Boolean;
    /// <summary>False bei leerem oder ungültigem Muster. AIndex darf nil sein (dann gibt es keine Unit-Namen).
    /// </summary>
    class function Parse(const AText: string; const AIndex: ISymbolIndex; out APattern: TMethodPattern): Boolean;
      static;
    /// <summary>Glob-Vergleich ohne Groß-/Kleinschreibung mit * (beliebig viele Zeichen) und ? (ein Zeichen).
    /// </summary>
    class function Matches(const AMask, AText: string): Boolean; static;
  end;

  TMethodBreakpointOptions = record
    Overrides: Boolean;
    Overloads: Boolean;
    /// <summary>Höchstens so viele Treffer; darüber Truncated.</summary>
    MaxHits: Integer;
    class function Default: TMethodBreakpointOptions; static;
  end;

{$SCOPEDENUMS ON}
  TMethodHitReason = (Match, Override_, Implementation_);
{$SCOPEDENUMS OFF}

  TMethodBreakpointHit = record
    UnitName: string;
    FileName: string;
    /// <summary>Umgebender Typ ohne Typargumente; '' bei freien Routinen.</summary>
    Container: string;
    Name: string;
    Signature: string;
    ParamTypes: TArray<string>;
    /// <summary>Zeile der Deklaration (ab 0).</summary>
    DeclarationLine: Integer;
    /// <summary>Kopf der Implementierung (ab 0); -1 ohne Rumpf.</summary>
    HeaderLine: Integer;
    /// <summary>Erster ausführbarer Befehl (ab 0); -1 ohne Rumpf.</summary>
    Line: Integer;
    Reason: TMethodHitReason;
    /// <summary>Bei Override_ und Implementation_: der Treffer, über den sie dazukam (TBasis.Validiere,
    /// IAuftrag.Pruefe).</summary>
    Via: string;
    function HasSource: Boolean;
  end;

  /// <summary>Rumpf einer Routine auf oberster Ebene einer Datei.</summary>
  TMethodBody = record
    Container: string;
    Name: string;
    HasParams: Boolean;
    ParamTypes: TArray<string>;
    HeaderLine: Integer;
    Line: Integer;
  end;

  /// <summary>Rümpfe der Datei AFileName (offenes Dokument vor der Platte); nil, wenn sie nicht lesbar ist.
  /// </summary>
  TMethodBodySource = reference to function(const AFileName: string): TArray<TMethodBody>;

  TLspMethodBreakpoints = class
  public const
    cCommand = 'atlas.server.methodBreakpoints';
    cMaxHits = 500;
    cFormat = 1;
  public
    /// <summary>Alle Routinen mit Rumpf auf oberster Ebene (keine lokalen), in Dateireihenfolge.</summary>
    class function Bodies(ATree: TSyntaxTree): TArray<TMethodBody>; static;
    /// <summary>Zeile des ersten ausführbaren Befehls der Routine ARoutine (RoutineDecl); -1 ohne Rumpf.
    /// </summary>
    class function FirstLine(ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Treffer zu APattern, sortiert nach Unit und Zeile der Deklaration, höchstens AOptions.MaxHits.
    /// </summary>
    class function Search(const AIndex: ISymbolIndex; const APattern: TMethodPattern;
      const AOptions: TMethodBreakpointOptions; const ABodies: TMethodBodySource;
      out ATruncated: Boolean): TArray<TMethodBreakpointHit>; static;
    /// <summary>Muster und Schalter aus dem ersten Argument; False, wenn es kein Objekt mit "pattern" ist.
    /// </summary>
    class function ReadRequest(const AArguments: TJSONArray; out APattern: string;
      out AOptions: TMethodBreakpointOptions): Boolean; static;
    class function ToJson(const APattern: string; const AHits: TArray<TMethodBreakpointHit>;
      ATruncated: Boolean): TJSONObject; static;
    class function ErrorToJson(const AMessage: string): TJSONObject; static;
    /// <summary>Meldung für ein ungültiges Muster in der Sprache der Texte.</summary>
    class function InvalidPattern(const APattern: string): string; static;
    class function ReasonName(AReason: TMethodHitReason): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Chars,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Implementations,
  Atlas.Common.Lsp.StepFilter,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TMethodBreakpointsText = (InvalidPattern);

const
  cTexts: array[TMethodBreakpointsText] of TAtlasText = (
    (De: 'Ungültiges Muster: '; En: 'Invalid pattern: '));

{$SCOPEDENUMS OFF}

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  cClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType];
  cTypeNodeKinds = [TSyntaxKind.ClassType .. TSyntaxKind.VariantPart];
  cReasonNames: array[TMethodHitReason] of string = ('match', 'override', 'implementation');

type
  /// <summary>Kandidat aus dem Index samt Unit.</summary>
  TCandidate = record
    UnitName: string;
    FileName: string;
    Symbol: TIndexSymbol;
    Reason: TMethodHitReason;
    Via: string;
  end;

{ Hilfsfunktionen }

function LastPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := AName;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

function ContainerPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := '';
  mDot := LastDelimiter('.', AName);
  if mDot > 0 then
  begin
    Result := Copy(AName, 1, mDot - 1);
  end;
end;

function HasWildcard(const AText: string): Boolean;
begin
  Result := (Pos('*', AText) > 0) or (Pos('?', AText) > 0);
end;

/// <summary>Typname zum Vergleich: ohne Typargumente, ohne Unit davor, klein.</summary>
function TypeKey(const AType: string): string;
begin
  Result := LowerCase(LastPart(TLspStepFilter.PlainName(Trim(AType))));
end;

function SameParams(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if TypeKey(A[mIndex]) <> TypeKey(B[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

function ParamKey(const ATypes: TArray<string>): string;
var
  mType: string;
begin
  Result := '';
  for mType in ATypes do
  begin
    Result := Result + TypeKey(mType) + ',';
  end;
end;

/// <summary>Passt der Typ AContainer (ohne Typargumente) zum Muster: ganz oder mit seinem letzten Teil
/// (TInnen für TAussen.TInnen).</summary>
function ContainerMatches(const AMask, AContainer: string): Boolean;
var
  mPlain: string;
begin
  if AMask = '*' then
  begin
    Exit(True);
  end;
  mPlain := TLspStepFilter.PlainName(AContainer);
  Result := TMethodPattern.Matches(AMask, mPlain) or
    ((Pos('.', AMask) = 0) and (mPlain <> '') and TMethodPattern.Matches(AMask, LastPart(mPlain)));
end;

{ TMethodPattern }

class function TMethodPattern.Matches(const AMask, AText: string): Boolean;
var
  mMask, mText: string;
  mM, mT, mStar, mMark: Integer;
begin
  mMask := LowerCase(AMask);
  mText := LowerCase(AText);
  mM := 1;
  mT := 1;
  mStar := 0;
  mMark := 0;
  while mT <= Length(mText) do
  begin
    if (mM <= Length(mMask)) and ((mMask[mM] = '?') or (mMask[mM] = mText[mT])) then
    begin
      Inc(mM);
      Inc(mT);
    end
    else if (mM <= Length(mMask)) and (mMask[mM] = '*') then
    begin
      mStar := mM;
      mMark := mT;
      Inc(mM);
    end
    else if mStar > 0 then
    begin
      mM := mStar + 1;
      Inc(mMark);
      mT := mMark;
    end
    else
    begin
      Exit(False);
    end;
  end;
  while (mM <= Length(mMask)) and (mMask[mM] = '*') do
  begin
    Inc(mM);
  end;
  Result := mM > Length(mMask);
end;

/// <summary>Parametertypen aus "Integer, const A: string; var B" (ohne Klammern); ein Eintrag mit Doppelpunkt
/// zählt mit dem Typ dahinter.</summary>
function ReadParamTypes(const AText: string; out ATypes: TArray<string>): Boolean;
var
  mPart, mType: string;
  mColon: Integer;
begin
  ATypes := nil;
  Result := True;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  for mPart in AText.Replace(';', ',').Split([',']) do
  begin
    mType := Trim(mPart);
    mColon := Pos(':', mType);
    if mColon > 0 then
    begin
      mType := Trim(Copy(mType, mColon + 1, MaxInt));
    end;
    if mType = '' then
    begin
      Exit(False);
    end;
    ATypes := ATypes + [mType];
  end;
end;

/// <summary>Nur Bezeichnerzeichen, Punkte zwischen Teilen und Platzhalter; Typargumente &lt;…&gt; fallen weg.
/// </summary>
function ValidPath(const APath: string): Boolean;
var
  mPart: string;
  mChar: Char;
begin
  Result := APath <> '';
  if not Result then
  begin
    Exit;
  end;
  for mPart in APath.Split(['.']) do
  begin
    if mPart = '' then
    begin
      Exit(False);
    end;
    for mChar in mPart do
    begin
      if not TTextChars.IsIdentChar(mChar) and (mChar <> '*') and (mChar <> '?') then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Ordnet den Teil vor dem Namen zu: ganze Unit, Typ in einer Unit oder nur Typ.</summary>
procedure AssignQualifier(const AQualifier: string; const AIndex: ISymbolIndex; var APattern: TMethodPattern);
var
  mUnit: TUnitIndex;
  mDot: Integer;
  mPrefix: string;
begin
  APattern.ContainerMask := AQualifier;
  if (AQualifier = '') or HasWildcard(AQualifier) or (AIndex = nil) then
  begin
    if AQualifier = '' then
    begin
      APattern.ContainerMask := '*';
    end;
    Exit;
  end;
  if AIndex.FindUnit(AQualifier, mUnit) then
  begin
    APattern.UnitName := mUnit.UnitName;
    APattern.ContainerMask := '*';
    Exit;
  end;
  // Längste Unit vorn: Kunde.Import.TKunde → Unit Kunde.Import, Typ TKunde.
  mPrefix := AQualifier;
  repeat
    mDot := LastDelimiter('.', mPrefix);
    if mDot = 0 then
    begin
      Break;
    end;
    mPrefix := Copy(mPrefix, 1, mDot - 1);
    if AIndex.FindUnit(mPrefix, mUnit) then
    begin
      APattern.UnitName := mUnit.UnitName;
      APattern.ContainerMask := Copy(AQualifier, Length(mPrefix) + 2, MaxInt);
      Exit;
    end;
  until False;
end;

class function TMethodPattern.Parse(const AText: string; const AIndex: ISymbolIndex;
  out APattern: TMethodPattern): Boolean;
var
  mText, mPath: string;
  mOpen: Integer;
begin
  APattern := Default(TMethodPattern);
  mText := Trim(AText);
  APattern.Text := mText;
  Result := False;
  if mText = '' then
  begin
    Exit;
  end;
  mPath := mText;
  mOpen := Pos('(', mText);
  if mOpen > 0 then
  begin
    if mText[Length(mText)] <> ')' then
    begin
      Exit;
    end;
    APattern.HasParams := True;
    if not ReadParamTypes(Copy(mText, mOpen + 1, Length(mText) - mOpen - 1), APattern.ParamTypes) then
    begin
      Exit;
    end;
    mPath := Trim(Copy(mText, 1, mOpen - 1));
  end;
  mPath := TLspStepFilter.PlainName(mPath).Replace(' ', '');
  if not ValidPath(mPath) then
  begin
    Exit;
  end;
  APattern.NameMask := LastPart(mPath);
  AssignQualifier(ContainerPart(mPath), AIndex, APattern);
  APattern.Exact := (ContainerPart(mPath) <> '') and not HasWildcard(ContainerPart(mPath));
  Result := True;
end;

{ TMethodBreakpointOptions }

class function TMethodBreakpointOptions.Default: TMethodBreakpointOptions;
begin
  Result.Overrides := True;
  Result.Overloads := True;
  Result.MaxHits := TLspMethodBreakpoints.cMaxHits;
end;

{ TMethodBreakpointHit }

function TMethodBreakpointHit.HasSource: Boolean;
begin
  Result := Line >= 0;
end;

{ Rümpfe }

function IsExecutable(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  case ANode.Kind of
    TSyntaxKind.EmptyStatement, TSyntaxKind.InlineConst:
      Result := False;
    TSyntaxKind.InlineVar:
      begin
        // Nur mit Wert: var X: Integer; erzeugt keinen Code.
        Result := False;
        for mIndex := 0 to ANode.ChildCount - 1 do
        begin
          if not (ANode[mIndex].Kind in cTypeNodeKinds) then
          begin
            Result := True;
          end;
        end;
      end;
  else
    Result := True;
  end;
end;

function FirstStatementLine(AContainer: TSyntaxNode): Integer;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := -1;
  for mIndex := 0 to AContainer.ChildCount - 1 do
  begin
    mChild := AContainer[mIndex];
    case mChild.Kind of
      // Diese Zeilen tragen selbst keinen Code: hinein.
      TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.LabeledStatement,
      TSyntaxKind.RepeatStatement:
        Result := FirstStatementLine(mChild);
      // Läuft nur bei einer Ausnahme.
      TSyntaxKind.ExceptBlock:
        Result := -1;
    else
      if IsExecutable(mChild) then
      begin
        Result := mChild.StartPos.Line;
      end;
    end;
    if Result >= 0 then
    begin
      Exit;
    end;
  end;
end;

class function TLspMethodBreakpoints.FirstLine(ARoutine: TSyntaxNode): Integer;
var
  mBlock: TSyntaxNode;
begin
  Result := -1;
  if ARoutine = nil then
  begin
    Exit;
  end;
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  if mBlock <> nil then
  begin
    Result := FirstStatementLine(mBlock);
    if Result < 0 then
    begin
      // Leerer Rumpf: das end trägt den Rücksprung.
      Result := mBlock.EndPos.Line;
    end;
    Exit;
  end;
  mBlock := ARoutine.FindChild(TSyntaxKind.AsmBlock);
  if mBlock <> nil then
  begin
    Result := mBlock.StartPos.Line;
    if mBlock.EndPos.Line > Result + 1 then
    begin
      Inc(Result);
    end;
  end;
end;

class function TLspMethodBreakpoints.Bodies(ATree: TSyntaxTree): TArray<TMethodBody>;
var
  mList: TArray<TMethodBody>;
begin
  mList := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    ATree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      var
        mBody: TMethodBody;
        mMin, mMax: Integer;
        mName: string;
        mHeader: TSyntaxNode;
      begin
        Result := TSyntaxSearchStep.Descend;
        if ANode.Kind <> TSyntaxKind.RoutineDecl then
        begin
          Exit;
        end;
        // Lokale Routinen und anonyme Methoden darin sind kein Ziel.
        Result := TSyntaxSearchStep.Skip;
        if (ANode.FindChild(TSyntaxKind.Block) = nil) and (ANode.FindChild(TSyntaxKind.AsmBlock) = nil) then
        begin
          Exit;
        end;
        mBody := Default(TMethodBody);
        mName := TLspStepFilter.PlainName(ANode.Name);
        mBody.Container := ContainerPart(mName);
        mBody.Name := LastPart(mName);
        // Die Parameter stehen im Kopf der Routine.
        mHeader := ANode.FindChild(TSyntaxKind.RoutineHeader);
        if mHeader = nil then
        begin
          mHeader := ANode;
        end;
        mBody.HasParams := mHeader.FindChild(TSyntaxKind.Parameters) <> nil;
        TIndexExtractor.ParamInfo(ANode, mMin, mMax, mBody.ParamTypes);
        mBody.HeaderLine := ANode.StartPos.Line;
        mBody.Line := TLspMethodBreakpoints.FirstLine(ANode);
        mList := mList + [mBody];
      end);
  end;
  Result := mList;
end;

{ Suche }

type
  /// <summary>Zustand einer Suche: Rümpfe je Datei gemerkt, Treffer ohne Doppelte.</summary>
  TMethodSearch = class
  private
    FIndex: ISymbolIndex;
    FPattern: TMethodPattern;
    FOptions: TMethodBreakpointOptions;
    FBodySource: TMethodBodySource;
    FBodies: TDictionary<string, TArray<TMethodBody>>;
    FSeen: TDictionary<string, Boolean>;
    FHits: TList<TMethodBreakpointHit>;
    function BodiesOf(const AFileName: string): TArray<TMethodBody>;
    function IsBodyHeader(const AFileName: string; ALine: Integer): Boolean;
    function SymbolMatches(const ASymbol: TIndexSymbol): Boolean;
    function Collect: TArray<TCandidate>;
    function DropBodies(const ACandidates: TArray<TCandidate>): TArray<TCandidate>;
    function DropOverloads(const ACandidates: TArray<TCandidate>): TArray<TCandidate>;
    function IsInterfaceMember(const AUnit: TUnitIndex; const AContainer: string): Boolean;
    procedure AddHit(const ACandidate: TCandidate);
    procedure AddOverrides(const ACandidate: TCandidate);
    procedure AddImplementations(const ACandidate: TCandidate);
    procedure AddMethodsOf(const ALocation: TSymbolLocation; const AName: string; const ASource: TCandidate;
      AReason: TMethodHitReason; AOnlyOverrides: Boolean);
    function ResolvedName(const AClass: TIndexSymbol; const AInterface, AName: string): string;
  public
    constructor Create(const AIndex: ISymbolIndex; const APattern: TMethodPattern;
      const AOptions: TMethodBreakpointOptions; const ABodies: TMethodBodySource);
    destructor Destroy; override;
    function Run(out ATruncated: Boolean): TArray<TMethodBreakpointHit>;
  end;

constructor TMethodSearch.Create(const AIndex: ISymbolIndex; const APattern: TMethodPattern;
  const AOptions: TMethodBreakpointOptions; const ABodies: TMethodBodySource);
begin
  inherited Create;
  FIndex := AIndex;
  FPattern := APattern;
  FOptions := AOptions;
  FBodySource := ABodies;
  FBodies := TDictionary<string, TArray<TMethodBody>>.Create;
  FSeen := TDictionary<string, Boolean>.Create;
  FHits := TList<TMethodBreakpointHit>.Create;
end;

destructor TMethodSearch.Destroy;
begin
  FHits.Free;
  FSeen.Free;
  FBodies.Free;
  inherited;
end;

function TMethodSearch.BodiesOf(const AFileName: string): TArray<TMethodBody>;
var
  mKey: string;
begin
  mKey := LowerCase(AFileName);
  if FBodies.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := nil;
  if Assigned(FBodySource) then
  begin
    Result := FBodySource(AFileName);
  end;
  FBodies.Add(mKey, Result);
end;

function TMethodSearch.IsBodyHeader(const AFileName: string; ALine: Integer): Boolean;
var
  mBody: TMethodBody;
begin
  for mBody in BodiesOf(AFileName) do
  begin
    if mBody.HeaderLine = ALine then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TMethodSearch.SymbolMatches(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind in cRoutineKinds) and TMethodPattern.Matches(FPattern.NameMask, ASymbol.Name) and
    ContainerMatches(FPattern.ContainerMask, ASymbol.Container) and
    (not FPattern.HasParams or SameParams(FPattern.ParamTypes, ASymbol.ParamTypes));
end;

function TMethodSearch.Collect: TArray<TCandidate>;
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mCandidate: TCandidate;
  mKeys: TDictionary<string, Boolean>;
  mKey: string;
begin
  Result := nil;
  mKeys := TDictionary<string, Boolean>.Create;
  try
    for mUnit in FIndex.Units do
    begin
      if (FPattern.UnitName <> '') and not SameText(mUnit.UnitName, FPattern.UnitName) then
      begin
        Continue;
      end;
      if mUnit.Library_ and not FPattern.Exact then
      begin
        Continue;
      end;
      for mSymbol in mUnit.Symbols do
      begin
        if not SymbolMatches(mSymbol) then
        begin
          Continue;
        end;
        // Deklaration und Implementierung mit gleicher Parameterliste nur einmal.
        mKey := LowerCase(mUnit.FileName + '|' + TLspStepFilter.PlainName(mSymbol.Container) + '|' + mSymbol.Name +
          '|') + ParamKey(mSymbol.ParamTypes);
        if mKeys.ContainsKey(mKey) then
        begin
          Continue;
        end;
        mKeys.Add(mKey, True);
        mCandidate := Default(TCandidate);
        mCandidate.UnitName := mUnit.UnitName;
        mCandidate.FileName := mUnit.SymbolFile(mSymbol);
        mCandidate.Symbol := mSymbol;
        mCandidate.Reason := TMethodHitReason.Match;
        Result := Result + [mCandidate];
      end;
    end;
  finally
    mKeys.Free;
  end;
end;

function SameRoutine(const A, B: TCandidate): Boolean;
begin
  Result := SameText(A.FileName, B.FileName) and SameText(TLspStepFilter.PlainName(A.Symbol.Container),
    TLspStepFilter.PlainName(B.Symbol.Container)) and SameText(A.Symbol.Name, B.Symbol.Name);
end;

function TMethodSearch.DropBodies(const ACandidates: TArray<TCandidate>): TArray<TCandidate>;
var
  mIndex, mOther: Integer;
  mAtBody: TArray<Boolean>;
  mHasDeclaration: Boolean;
begin
  // Ein Treffer auf einem Rumpfkopf ist die Implementierung einer schon gefundenen Deklaration (Kurzform ohne
  // Parameter); nur Routinen, die allein im implementation-Teil stehen, sind ihre eigene Deklaration.
  SetLength(mAtBody, Length(ACandidates));
  for mIndex := 0 to High(ACandidates) do
  begin
    mAtBody[mIndex] := IsBodyHeader(ACandidates[mIndex].FileName,
      ACandidates[mIndex].Symbol.SelectionRange.StartPos.Line) or IsBodyHeader(ACandidates[mIndex].FileName,
      ACandidates[mIndex].Symbol.Range.StartPos.Line);
  end;
  Result := nil;
  for mIndex := 0 to High(ACandidates) do
  begin
    if mAtBody[mIndex] then
    begin
      mHasDeclaration := False;
      for mOther := 0 to High(ACandidates) do
      begin
        if (mOther <> mIndex) and not mAtBody[mOther] and SameRoutine(ACandidates[mIndex], ACandidates[mOther]) then
        begin
          mHasDeclaration := True;
          Break;
        end;
      end;
      if mHasDeclaration then
      begin
        Continue;
      end;
    end;
    Result := Result + [ACandidates[mIndex]];
  end;
end;

function TMethodSearch.DropOverloads(const ACandidates: TArray<TCandidate>): TArray<TCandidate>;
var
  mCandidate, mKept: TCandidate;
  mFound: Boolean;
begin
  if FOptions.Overloads or FPattern.HasParams then
  begin
    Exit(ACandidates);
  end;
  Result := nil;
  for mCandidate in ACandidates do
  begin
    mFound := False;
    for mKept in Result do
    begin
      if SameRoutine(mCandidate, mKept) then
      begin
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mCandidate];
    end;
  end;
end;

function TMethodSearch.IsInterfaceMember(const AUnit: TUnitIndex; const AContainer: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  if AContainer = '' then
  begin
    Exit(False);
  end;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.InterfaceType) and SameText(mSymbol.QualifiedName, AContainer) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Treffer für ACandidate, noch ohne Zeilen des Rumpfs.</summary>
function HitOf(const ACandidate: TCandidate): TMethodBreakpointHit;
begin
  Result := Default(TMethodBreakpointHit);
  Result.UnitName := ACandidate.UnitName;
  Result.FileName := ACandidate.FileName;
  Result.Container := TLspStepFilter.PlainName(ACandidate.Symbol.Container);
  Result.Name := ACandidate.Symbol.Name;
  Result.Signature := ACandidate.Symbol.Signature;
  Result.ParamTypes := ACandidate.Symbol.ParamTypes;
  Result.DeclarationLine := ACandidate.Symbol.SelectionRange.StartPos.Line;
  Result.Reason := ACandidate.Reason;
  Result.Via := ACandidate.Via;
  Result.HeaderLine := -1;
  Result.Line := -1;
end;

/// <summary>Rumpf des Treffers AHit unter ABodies: bei Überladungen der mit denselben Parametertypen, sonst der
/// erste mit dem Namen; -1 ohne.</summary>
function BodyOfHit(const ABodies: TArray<TMethodBody>; const AHit: TMethodBreakpointHit): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ABodies) do
  begin
    if not SameText(ABodies[mIndex].Container, AHit.Container) or not SameText(ABodies[mIndex].Name, AHit.Name) then
    begin
      Continue;
    end;
    if ABodies[mIndex].HasParams and SameParams(ABodies[mIndex].ParamTypes, AHit.ParamTypes) then
    begin
      Exit(mIndex);
    end;
    if Result < 0 then
    begin
      Result := mIndex;
    end;
  end;
end;

procedure TMethodSearch.AddHit(const ACandidate: TCandidate);
var
  mHit: TMethodBreakpointHit;
  mKey: string;
  mBodies: TArray<TMethodBody>;
  mBody: Integer;
begin
  if ACandidate.Symbol.HasDirective('abstract') or ACandidate.Symbol.HasDirective('external') then
  begin
    Exit;
  end;
  if not FOptions.Overrides and ACandidate.Symbol.HasDirective('override') then
  begin
    Exit;
  end;
  mHit := HitOf(ACandidate);
  mKey := LowerCase(mHit.FileName + '|' + mHit.Container + '|' + mHit.Name + '|') + ParamKey(mHit.ParamTypes);
  if FSeen.ContainsKey(mKey) then
  begin
    Exit;
  end;
  FSeen.Add(mKey, True);
  mBodies := BodiesOf(mHit.FileName);
  mBody := BodyOfHit(mBodies, mHit);
  if mBody >= 0 then
  begin
    mHit.HeaderLine := mBodies[mBody].HeaderLine;
    mHit.Line := mBodies[mBody].Line;
  end;
  FHits.Add(mHit);
end;

procedure TMethodSearch.AddMethodsOf(const ALocation: TSymbolLocation; const AName: string;
  const ASource: TCandidate; AReason: TMethodHitReason; AOnlyOverrides: Boolean);
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mCandidate: TCandidate;
  mTypeName: string;
begin
  if not FIndex.FindFile(ALocation.FileName, mUnit) then
  begin
    Exit;
  end;
  mTypeName := ALocation.Symbol.QualifiedName;
  for mSymbol in mUnit.Symbols do
  begin
    if not (mSymbol.Kind in cRoutineKinds) or not SameText(mSymbol.Container, mTypeName) or
      not SameText(mSymbol.Name, AName) then
    begin
      Continue;
    end;
    if AOnlyOverrides and not mSymbol.HasDirective('override') then
    begin
      Continue;
    end;
    if FPattern.HasParams and not SameParams(FPattern.ParamTypes, mSymbol.ParamTypes) then
    begin
      Continue;
    end;
    mCandidate := Default(TCandidate);
    mCandidate.UnitName := mUnit.UnitName;
    mCandidate.FileName := mUnit.SymbolFile(mSymbol);
    mCandidate.Symbol := mSymbol;
    mCandidate.Reason := AReason;
    mCandidate.Via := TLspStepFilter.PlainName(ASource.Symbol.Container) + '.' + ASource.Symbol.Name;
    // Der Rumpf in der Implementierung steht unter demselben Schlüssel: AddHit nimmt nur den ersten.
    AddHit(mCandidate);
    if not FOptions.Overloads and not FPattern.HasParams then
    begin
      Break;
    end;
  end;
end;

procedure TMethodSearch.AddOverrides(const ACandidate: TCandidate);
var
  mLocation: TSymbolLocation;
begin
  if not FOptions.Overrides or not ACandidate.Symbol.IsVirtual or (ACandidate.Symbol.Container = '') then
  begin
    Exit;
  end;
  for mLocation in TLspImplementations.AllDescendantsOf(FIndex, ACandidate.Symbol.Container) do
  begin
    if mLocation.Symbol.Kind in cClassKinds then
    begin
      AddMethodsOf(mLocation, ACandidate.Symbol.Name, ACandidate, TMethodHitReason.Override_, True);
    end;
  end;
end;

function TMethodSearch.ResolvedName(const AClass: TIndexSymbol; const AInterface, AName: string): string;
var
  mEntry, mLeft: string;
  mEquals: Integer;
begin
  // Methodenzuordnung "IAuftrag.Pruefe=MeinePruefung" im Klassenrumpf.
  Result := AName;
  for mEntry in AClass.Resolutions do
  begin
    mEquals := Pos('=', mEntry);
    if mEquals = 0 then
    begin
      Continue;
    end;
    mLeft := Trim(Copy(mEntry, 1, mEquals - 1));
    if SameText(TypeKey(ContainerPart(mLeft)), TypeKey(AInterface)) and SameText(LastPart(mLeft), AName) then
    begin
      Exit(Trim(Copy(mEntry, mEquals + 1, MaxInt)));
    end;
  end;
end;

procedure TMethodSearch.AddImplementations(const ACandidate: TCandidate);
var
  mLocation: TSymbolLocation;
  mInterface: string;
begin
  mInterface := ACandidate.Symbol.Container;
  for mLocation in TLspImplementations.AllDescendantsOf(FIndex, mInterface) do
  begin
    if not (mLocation.Symbol.Kind in cClassKinds) then
    begin
      Continue;
    end;
    // Nachfahren einer umsetzenden Klasse überschreiben nur; ohne "Überschreibungen" fallen sie weg (AddHit).
    AddMethodsOf(mLocation, ResolvedName(mLocation.Symbol, mInterface, ACandidate.Symbol.Name), ACandidate,
      TMethodHitReason.Implementation_, False);
  end;
end;

function CompareHits(const A, B: TMethodBreakpointHit): Integer;
begin
  Result := CompareText(A.UnitName, B.UnitName);
  if Result = 0 then
  begin
    Result := CompareText(A.FileName, B.FileName);
  end;
  if Result = 0 then
  begin
    Result := A.DeclarationLine - B.DeclarationLine;
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.Container + '.' + A.Name, B.Container + '.' + B.Name);
  end;
  if Result = 0 then
  begin
    Result := CompareText(ParamKey(A.ParamTypes), ParamKey(B.ParamTypes));
  end;
end;

function TMethodSearch.Run(out ATruncated: Boolean): TArray<TMethodBreakpointHit>;
var
  mCandidates: TArray<TCandidate>;
  mCandidate: TCandidate;
  mUnit: TUnitIndex;
  mHits: TArray<TMethodBreakpointHit>;
begin
  ATruncated := False;
  Result := nil;
  if FIndex = nil then
  begin
    Exit;
  end;
  mCandidates := DropOverloads(DropBodies(Collect));
  for mCandidate in mCandidates do
  begin
    if FIndex.FindFile(mCandidate.FileName, mUnit) and IsInterfaceMember(mUnit, mCandidate.Symbol.Container) then
    begin
      AddImplementations(mCandidate);
      Continue;
    end;
    AddHit(mCandidate);
  end;
  // Überschreibungen erst nach allen direkten Treffern, damit ein Treffer, der selbst passt, "match" bleibt.
  for mCandidate in mCandidates do
  begin
    AddOverrides(mCandidate);
  end;
  mHits := FHits.ToArray;
  TArray.Sort<TMethodBreakpointHit>(mHits, TComparer<TMethodBreakpointHit>.Construct(CompareHits));
  if (FOptions.MaxHits > 0) and (Length(mHits) > FOptions.MaxHits) then
  begin
    SetLength(mHits, FOptions.MaxHits);
    ATruncated := True;
  end;
  Result := mHits;
end;

{ TLspMethodBreakpoints }

class function TLspMethodBreakpoints.Search(const AIndex: ISymbolIndex; const APattern: TMethodPattern;
  const AOptions: TMethodBreakpointOptions; const ABodies: TMethodBodySource;
  out ATruncated: Boolean): TArray<TMethodBreakpointHit>;
var
  mSearch: TMethodSearch;
begin
  mSearch := TMethodSearch.Create(AIndex, APattern, AOptions, ABodies);
  try
    Result := mSearch.Run(ATruncated);
  finally
    mSearch.Free;
  end;
end;

class function TLspMethodBreakpoints.ReadRequest(const AArguments: TJSONArray; out APattern: string;
  out AOptions: TMethodBreakpointOptions): Boolean;
var
  mObject: TJSONObject;
  mValue: TJSONValue;
begin
  APattern := '';
  AOptions := TMethodBreakpointOptions.Default;
  Result := (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject);
  if not Result then
  begin
    Exit;
  end;
  mObject := TJSONObject(AArguments.Items[0]);
  mValue := mObject.GetValue('pattern');
  Result := mValue is TJSONString;
  if not Result then
  begin
    Exit;
  end;
  APattern := TJSONString(mValue).Value;
  mValue := mObject.GetValue('overrides');
  if mValue is TJSONBool then
  begin
    AOptions.Overrides := TJSONBool(mValue).AsBoolean;
  end;
  mValue := mObject.GetValue('overloads');
  if mValue is TJSONBool then
  begin
    AOptions.Overloads := TJSONBool(mValue).AsBoolean;
  end;
end;

class function TLspMethodBreakpoints.ReasonName(AReason: TMethodHitReason): string;
begin
  Result := cReasonNames[AReason];
end;

class function TLspMethodBreakpoints.ToJson(const APattern: string; const AHits: TArray<TMethodBreakpointHit>;
  ATruncated: Boolean): TJSONObject;
var
  mHits: TJSONArray;
  mHit: TMethodBreakpointHit;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('format', TJSONNumber.Create(cFormat));
    Result.AddPair('pattern', APattern);
    Result.AddPair('truncated', TJSONBool.Create(ATruncated));
    mHits := TJSONArray.Create;
    Result.AddPair('hits', mHits);
    for mHit in AHits do
    begin
      mItem := TJSONObject.Create;
      mHits.AddElement(mItem);
      mItem.AddPair('uri', TDocumentUris.FromPath(mHit.FileName));
      mItem.AddPair('unit', mHit.UnitName);
      mItem.AddPair('container', mHit.Container);
      mItem.AddPair('name', mHit.Name);
      mItem.AddPair('signature', mHit.Signature);
      mItem.AddPair('declarationLine', TJSONNumber.Create(mHit.DeclarationLine));
      mItem.AddPair('headerLine', TJSONNumber.Create(mHit.HeaderLine));
      mItem.AddPair('line', TJSONNumber.Create(mHit.Line));
      mItem.AddPair('source', TJSONBool.Create(mHit.HasSource));
      mItem.AddPair('reason', ReasonName(mHit.Reason));
      mItem.AddPair('via', mHit.Via);
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TLspMethodBreakpoints.ErrorToJson(const AMessage: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format', TJSONNumber.Create(cFormat));
  Result.AddPair('error', AMessage);
end;

class function TLspMethodBreakpoints.InvalidPattern(const APattern: string): string;
begin
  Result := cTexts[TMethodBreakpointsText.InvalidPattern].Text + APattern;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.MethodBreakpoints', cTexts);

end.
