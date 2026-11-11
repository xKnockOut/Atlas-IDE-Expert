unit Atlas.Common.Editing.Extract.Shared;

// Gemeinsame Teile der Extrahieren-Aktionen (#50, #980), die Atlas.Common.Editing.Extract und
// Atlas.Common.Editing.Extract.Method brauchen: Optionen und Typprobe, Auswahl auf Token zuschneiden, Sperren
// (anonyme Methode, with, asm), Typ eines Ausdrucks, Kopf der neuen Routine samt Deklaration in der Klasse und
// die Signatur der neuen Routine (Parameter, Argumente, lokale Variablen und Konstanten).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.RoutineLocals;

const
  /// <summary>Art der Extrahieren-Aktionen (LSP).</summary>
  cExtractKind = 'refactor.extract';
  /// <summary>Name der Inline-Variablen im Probetext für die Typabfrage.</summary>
  cExtractProbeName = 'AtlasProbe';
  /// <summary>Name der neuen Methode bei „Methode extrahieren“.</summary>
  cExtractedMethodName = 'ExtractedMethod';

type
  /// <summary>Typ eines Ausdrucks laut Namensauflösung.</summary>
  TProbedType = record
    /// <summary>Typ wie im Quelltext; '' unbekannt.</summary>
    Name: string;
    /// <summary>Unit, die für den Typ ins uses muss; '' wenn er sichtbar ist.</summary>
    UnitName: string;
    /// <summary>Klasse, Interface oder Zeiger: Eine Kopie zeigt auf dasselbe Objekt.</summary>
    IsReference: Boolean;
    /// <summary>Record oder anderer Werttyp: Eine Kopie ist ein eigener Wert.</summary>
    IsValue: Boolean;
    /// <summary>Record (bzw. object): für const-Parameter (#472).</summary>
    IsRecord: Boolean;
    /// <summary>Interface: für const-Parameter und weil es keine Rümpfe hat (#472).</summary>
    IsInterface: Boolean;
    /// <summary>Deklarierende Unit, auch wenn der Typ sichtbar ist; '' bei eingebauten Typen.</summary>
    TypeUnit: string;
  end;

  /// <summary>Typ der Inline-Variablen ohne Typangabe, deren Name in AText an ANamePos steht.</summary>
  TTypeProbe = reference to function(const AText: string; const ANamePos: TTextPosition): TProbedType;

  TExtractOptions = record
    /// <summary>Inline-Variablen erzeugen (Einstellung und Sprachversion).</summary>
    InlineVar: Boolean;
    Style: TFormatStyle;
    /// <summary>Namensauflösung für Typen; nil ohne.</summary>
    Probe: TTypeProbe;
    /// <summary>Präfixe neuer Namen nach der Namensregel (#1111): Konstante einführen → cNewConstant; ohne leer.
    /// </summary>
    Names: TPascalNamePrefixes;
    /// <summary>Zu „Methode extrahieren“ auch gleiche Stellen der Unit anbieten (#2054,
    /// refactoring.extractMethodDuplicates).</summary>
    Duplicates: Boolean;
    /// <summary>Wunschname der neuen Methode (MCP extract_method); '' ExtractedMethod.</summary>
    MethodName: string;
    class function Default: TExtractOptions; static;
  end;

  /// <summary>Was der Kopf einer neuen Routine braucht.</summary>
  TRoutineHeadRequest = record
    /// <summary>Umgebende Routine; die neue steht davor bzw. wird Methode derselben Klasse.</summary>
    Routine: TSyntaxNode;
    Body: TSyntaxNode;
    /// <summary>Wunschname, eindeutig gemacht in TRoutineHead.ShortName.</summary>
    BaseName: string;
    /// <summary>procedure oder function.</summary>
    Kind: string;
    /// <summary>Parameter samt Klammern; '' ohne.</summary>
    Params: string;
    /// <summary>Rückgabe samt Doppelpunkt, z. B. ': Boolean'; '' ohne.</summary>
    ResultType: string;
    Style: TFormatStyle;
  end;

  TRoutineHead = record
    ShortName: string;
    /// <summary>Erste Zeile der Implementierung samt Zeilenumbruch.</summary>
    Text: string;
    /// <summary>Grund, wenn der Kopf nicht entstehen kann.</summary>
    Reason: string;
  end;

  /// <summary>Hilfen der Extrahieren-Aktionen.</summary>
  TExtractSupport = class
  public
    /// <summary>Offsets von ARange; False, wenn der Anfang hinter dem Ende liegt.</summary>
    class function OffsetRange(const AText: string; const ARange: TTextRange; out AFirst, ALast: Integer): Boolean;
      static;
    /// <summary>Auswahl auf Token zuschneiden: Leerraum, Kommentare und ";" am Rand zählen nicht.</summary>
    class function Trimmed(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      out AStart, AEnd: Integer): Boolean; static;
    /// <summary>Nicht leere Auswahl ARange, auf Token zugeschnitten.</summary>
    class function Selection(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
      out AStart, AEnd: Integer): Boolean; static;
    class function InSelection(ANode: TSyntaxNode; AStart, AEnd: Integer): Boolean; static;
    /// <summary>Kommentar, Direktive oder ";": zählt am Rand und zwischen Anweisungen nicht.</summary>
    class function IsFiller(const AToken: TPascalToken): Boolean; static;
    /// <summary>Normalform eines Knotens für den Vergleich: Token ohne Kommentare, Groß- und Kleinschreibung
    /// egal außer in String-Literalen. Direktiven nur mit AKeepDirectives (gleiche Stellen, #2054: ein anderes
    /// {$IFDEF} ändert die Bedeutung).</summary>
    class function NormalText(ATree: TSyntaxTree; ANode: TSyntaxNode; AKeepDirectives: Boolean = False): string;
      static;
    /// <summary>Liegt ANode in einer anonymen Methode, einem with-Rumpf oder asm innerhalb von ABody? Dort hätten
    /// Namen in einer neuen Routine eine andere Bedeutung.</summary>
    class function InsideBlocked(ANode, ABody: TSyntaxNode; out AReason: string): Boolean; static;
    /// <summary>Namen, die nur in der umgebenden Routine sichtbar sind: verschachtelte Routinen, lokale Typen
    /// und Marken.</summary>
    class function RoutineOnlyNames(ARoutine: TSyntaxNode): TArray<string>; static;
    /// <summary>Typ eines Ausdrucks (Knoten AExpression), der als Inline-Variable vor AStatement stünde:
    /// erst AOptions.Probe, dann Literal, Operator und Bezeichner der Datei. Name '' unbekannt.</summary>
    class function TypeOfExpression(const AText: string; ATree: TSyntaxTree; AExpression,
      AStatement: TSyntaxNode; const AOptions: TExtractOptions): TProbedType; static;
    /// <summary>uses-Eintrag für den Typ, wenn die Namensauflösung eine fehlende Unit meldet.</summary>
    class procedure AddUsesFor(ATree: TSyntaxTree; const AText: string; const AType: TProbedType;
      AOffset: Integer; var AEdits: TArray<TTextEdit>); static;
    /// <summary>Erste Zeile der neuen Routine vor ARequest.Routine: Methode der Klasse samt Deklaration im
    /// private-Abschnitt (Edit in AEdits) oder Routine davor. False mit Grund in AHead.Reason.</summary>
    class function NewRoutineHead(const AText: string; ATree: TSyntaxTree; const ARequest: TRoutineHeadRequest;
      var AEdits: TArray<TTextEdit>; out AHead: TRoutineHead): Boolean; static;
  end;

  /// <summary>Signatur und Rumpf der neuen Routine: Parameter, Argumente des Aufrufs, lokale Variablen und
  /// mitkopierte Konstanten.</summary>
  TExtractSignature = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FRoutine: TSyntaxNode;
    FOptions: TExtractOptions;
    FIndent: string;
    FIndentUnit: string;
    FLineBreak: string;
    FParams: string;
    FArgs: string;
    FVarLines: string;
    FConstLines: string;
    FEdits: TArray<TTextEdit>;
    function Declarations: string;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; ARoutine: TSyntaxNode;
      const AOptions: TExtractOptions);
    /// <summary>Typ von ALocal, notfalls über die Typprobe (uses-Eintrag in Edits); False, wenn unbekannt.
    /// </summary>
    function LocalType(const ALocal: TRoutineLocal; out AType: string): Boolean;
    /// <summary>Lokale Konstante wörtlich in den const-Abschnitt der neuen Routine.</summary>
    procedure AddConstant(const ALocal: TRoutineLocal);
    procedure AddVariable(const AName, AType: string);
    /// <summary>AModifier z. B. 'const ', 'var ' oder ''.</summary>
    procedure AddParameter(const AModifier, AName, AType: string);
    /// <summary>Parameter samt Klammern; '' ohne.</summary>
    function ParamsText: string;
    /// <summary>Argumente des Aufrufs samt Klammern; '' ohne.</summary>
    function ArgsText: string;
    /// <summary>Kopf, var- und const-Abschnitt und Rumpf aus ABody (eingerückt wie ABodyIndent), eine Ebene
    /// unter begin.</summary>
    function RoutineText(const AHead, ABody, ABodyIndent: string): string;
    /// <summary>Kopf AHead mit var- und const-Abschnitt: vergleicht neue Routinen ohne Rumpf (#2054).</summary>
    function Key(const AHead: string): string;
    property Edits: TArray<TTextEdit> read FEdits write FEdits;
  end;

/// <summary>Setzt AOut auf AReason und liefert False.</summary>
function Fail(const AReason: string; out AOut: string): Boolean;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Editing.DeclareUnknown,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSharedText = (InAnAnonymousMethod, ClassNotInTheFile, ClassDeclarationCannotBeExtended, InAWithBody);

const
  cTexts: array[TSharedText] of TAtlasText = (
    (De: 'in einer anonymen Methode'; En: 'in an anonymous method'),
    (De: 'Klasse %s nicht in der Datei'; En: 'Class %s not in the file'),
    (De: 'Klassendeklaration nicht erweiterbar'; En: 'class declaration cannot be extended'),
    (De: 'in einem with-Rumpf'; En: 'in a with body'));

{$SCOPEDENUMS OFF}

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

{ TExtractOptions }

class function TExtractOptions.Default: TExtractOptions;
begin
  Result.InlineVar := True;
  Result.Style := TFormatStyle.Default;
  Result.Probe := nil;
  Result.Names := TPascalNamePrefixes.None;
  Result.Duplicates := False;
  Result.MethodName := '';
end;

{ TExtractSupport }

class function TExtractSupport.OffsetRange(const AText: string; const ARange: TTextRange;
  out AFirst, ALast: Integer): Boolean;
var
  mLines: TLineTable;
begin
  mLines := TLineTable.Build(AText);
  AFirst := mLines.OffsetAt(ARange.StartPos);
  ALast := mLines.OffsetAt(ARange.EndPos);
  Result := AFirst <= ALast;
end;

class function TExtractSupport.IsFiller(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) or AToken.IsSymbol(';');
end;

class function TExtractSupport.NormalText(ATree: TSyntaxTree; ANode: TSyntaxNode; AKeepDirectives: Boolean): string;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mSkipped: set of TPascalTokenKind;
begin
  mSkipped := [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
  if AKeepDirectives then
  begin
    mSkipped := [TPascalTokenKind.Comment];
  end;
  mTokens := ATree.Tokens;
  Result := '';
  mIndex := TRoutineBody.TokenAt(mTokens, ANode.StartOffset);
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if mTokens[mIndex].Kind = TPascalTokenKind.StringLiteral then
    begin
      Result := Result + mTokens[mIndex].Text + ' ';
    end
    else if not (mTokens[mIndex].Kind in mSkipped) then
    begin
      Result := Result + LowerCase(mTokens[mIndex].Text) + ' ';
    end;
    Inc(mIndex);
  end;
end;

class function TExtractSupport.Trimmed(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  out AStart, AEnd: Integer): Boolean;
var
  mFirst, mLast: Integer;
begin
  mFirst := TRoutineBody.TokenAt(ATokens, AFirst);
  while (mFirst <= High(ATokens)) and (ATokens[mFirst].Offset < ALast) and IsFiller(ATokens[mFirst]) do
  begin
    Inc(mFirst);
  end;
  mLast := TRoutineBody.TokenAt(ATokens, ALast) - 1;
  while (mLast >= mFirst) and IsFiller(ATokens[mLast]) do
  begin
    Dec(mLast);
  end;
  Result := (mFirst <= High(ATokens)) and (mLast >= mFirst) and (ATokens[mLast].Offset < ALast);
  if Result then
  begin
    AStart := ATokens[mFirst].Offset;
    AEnd := ATokens[mLast].Offset + Length(ATokens[mLast].Text);
  end;
end;

class function TExtractSupport.Selection(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
  out AStart, AEnd: Integer): Boolean;
var
  mFirst, mLast: Integer;
begin
  Result := (ATree <> nil) and OffsetRange(AText, ARange, mFirst, mLast) and (mFirst <> mLast) and
    Trimmed(ATree.Tokens, mFirst, mLast, AStart, AEnd);
end;

class function TExtractSupport.InSelection(ANode: TSyntaxNode; AStart, AEnd: Integer): Boolean;
begin
  Result := (ANode.StartOffset >= AStart) and (ANode.EndOffset <= AEnd);
end;

class function TExtractSupport.InsideBlocked(ANode, ABody: TSyntaxNode; out AReason: string): Boolean;
var
  mNode: TSyntaxNode;
begin
  AReason := '';
  mNode := ANode.Parent;
  while (AReason = '') and (mNode <> nil) and (mNode <> ABody) do
  begin
    case mNode.Kind of
      TSyntaxKind.AnonymousMethod:
        AReason := cTexts[TSharedText.InAnAnonymousMethod].Text;
      TSyntaxKind.WithStatement:
        AReason := cTexts[TSharedText.InAWithBody].Text;
      TSyntaxKind.AsmBlock:
        AReason := 'asm';
    else
      // Übrige Knoten sperren nicht.
    end;
    mNode := mNode.Parent;
  end;
  Result := AReason <> '';
end;

class function TExtractSupport.RoutineOnlyNames(ARoutine: TSyntaxNode): TArray<string>;
var
  mIndex, mInner: Integer;
  mName: string;
begin
  Result := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    case ARoutine[mIndex].Kind of
      TSyntaxKind.RoutineDecl:
        begin
          mName := ARoutine[mIndex].Name;
          Result := Result + [mName.Substring(mName.LastIndexOf('.') + 1)];
        end;
      TSyntaxKind.TypeSection:
        for mInner := 0 to ARoutine[mIndex].ChildCount - 1 do
        begin
          Result := Result + [ARoutine[mIndex][mInner].Name];
        end;
    else
      // Übrige Deklarationen sind auch außerhalb sichtbar.
    end;
  end;
end;

/// <summary>Probetext: AText mit "var AtlasProbe := Ausdruck;" vor AStatement; ANamePos ist die Stelle des
/// Namens.</summary>
function ProbeText(const AText, AExpression: string; AStatement: TSyntaxNode; out ANamePos: TTextPosition): string;
begin
  ANamePos := TTextPosition.Create(AStatement.StartPos.Line, AStatement.StartPos.Character + 4);
  Result := Copy(AText, 1, AStatement.StartOffset) + 'var ' + cExtractProbeName + ' := ' + AExpression + '; ' +
    Copy(AText, AStatement.StartOffset + 1, MaxInt);
end;

/// <summary>Typ des einzelnen Terms ATerm: deklarierter Typ eines Bezeichners der Datei bzw. Typ des Literals.
/// </summary>
function TermType(const AText: string; ATree: TSyntaxTree; const ATerm: TPascalToken): string;
var
  mDeclared: TDeclaredTypes;
begin
  if ATerm.Kind <> TPascalTokenKind.Identifier then
  begin
    Exit(TDeclareUnknown.LiteralType(ATerm));
  end;
  mDeclared := TDeclaredTypes.Create(ATree, AText);
  try
    Result := mDeclared.DeclaredType(ATerm.Text, ATerm.StartPos);
  finally
    mDeclared.Free;
  end;
end;

/// <summary>Typ aus Literal, einfachem Operator oder Bezeichner der Datei; '' unbekannt.</summary>
function LocalExpressionType(const AText: string; ATree: TSyntaxTree; AExpression: TSyntaxNode): string;
var
  mTokens: TArray<TPascalToken>;
  mFirst, mLast, mTermFirst, mTermLast: Integer;
begin
  Result := '';
  mTokens := ATree.Tokens;
  mFirst := TRoutineBody.TokenAt(mTokens, AExpression.StartOffset);
  mLast := TRoutineBody.TokenAt(mTokens, AExpression.EndOffset) - 1;
  if (mFirst > mLast) or (mLast > High(mTokens)) then
  begin
    Exit;
  end;
  if mFirst = mLast then
  begin
    Result := TDeclareUnknown.LiteralType(mTokens[mFirst]);
  end;
  if Result = '' then
  begin
    Result := TDeclareUnknown.Shape(mTokens, mFirst, mLast, mTermFirst, mTermLast);
  end;
  if (Result = '') and (mTermFirst >= 0) and (mTermFirst = mTermLast) then
  begin
    Result := TermType(AText, ATree, mTokens[mTermFirst]);
  end;
end;

class function TExtractSupport.TypeOfExpression(const AText: string; ATree: TSyntaxTree; AExpression,
  AStatement: TSyntaxNode; const AOptions: TExtractOptions): TProbedType;
var
  mNamePos: TTextPosition;
begin
  Result := Default(TProbedType);
  if Assigned(AOptions.Probe) then
  begin
    Result := AOptions.Probe(ProbeText(AText, TRoutineBody.TextOf(AText, AExpression), AStatement, mNamePos),
      mNamePos);
  end;
  if Result.Name = '' then
  begin
    Result.Name := LocalExpressionType(AText, ATree, AExpression);
    Result.IsValue := Result.Name <> '';
  end;
end;

class procedure TExtractSupport.AddUsesFor(ATree: TSyntaxTree; const AText: string; const AType: TProbedType;
  AOffset: Integer; var AEdits: TArray<TTextEdit>);
var
  mEdit: TTextEdit;
begin
  if (AType.UnitName <> '') and TUsesClauses.AddUnit(ATree.Tokens, AOffset, AType.UnitName,
    TTextLines.LineBreakOf(AText), mEdit) then
  begin
    AEdits := AEdits + [mEdit];
  end;
end;

function IsClassRoutine(const ATokens: TArray<TPascalToken>; ARoutine: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, ARoutine.StartOffset);
  Result := (mIndex <= High(ATokens)) and ATokens[mIndex].IsKeyword('class');
end;

/// <summary>Klasse einer Methode ("TAussen.TInnen"); '' bei freien und verschachtelten Routinen.</summary>
function QualifierOf(ARoutine: TSyntaxNode): string;
var
  mName: string;
begin
  Result := '';
  mName := ARoutine.Name;
  if (mName.LastIndexOf('.') > 0) and (ARoutine.Parent <> nil) and
    (ARoutine.Parent.Kind <> TSyntaxKind.RoutineDecl) then
  begin
    Result := mName.Substring(0, mName.LastIndexOf('.'));
  end;
end;

/// <summary>Name der innersten Klasse ohne Typparameter.</summary>
function ClassNameOf(const AQualifier: string): string;
begin
  Result := AQualifier.Substring(AQualifier.LastIndexOf('.') + 1);
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

/// <summary>Steht "static" im Kopf der Routine (vor ihrem Rumpf)?</summary>
function IsStaticRoutine(const ATokens: TArray<TPascalToken>; ARoutine, ABody: TSyntaxNode): Boolean;
var
  mToken: Integer;
begin
  Result := False;
  mToken := TRoutineBody.TokenAt(ATokens, ARoutine.StartOffset);
  while not Result and (mToken <= High(ATokens)) and (ATokens[mToken].Offset < ABody.StartOffset) do
  begin
    Result := (ATokens[mToken].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mToken].Text, 'static');
    Inc(mToken);
  end;
end;

class function TExtractSupport.NewRoutineHead(const AText: string; ATree: TSyntaxTree;
  const ARequest: TRoutineHeadRequest; var AEdits: TArray<TTextEdit>; out AHead: TRoutineHead): Boolean;
var
  mHeader, mSignature, mQualifier, mClassDecl, mIndent: string;
  mTypeBody: TSyntaxNode;
  mEdit: TTextEdit;
begin
  AHead := Default(TRoutineHead);
  mIndent := TTextLines.IndentOf(AText, ARequest.Routine.StartPos.Line);
  AHead.ShortName := TRoutineBody.UniqueName(ATree.Tokens, ARequest.BaseName);
  mHeader := ARequest.Kind + ' ';
  if IsClassRoutine(ATree.Tokens, ARequest.Routine) then
  begin
    mHeader := 'class ' + mHeader;
  end;
  mSignature := AHead.ShortName + ARequest.Params + ARequest.ResultType + ';';
  mQualifier := QualifierOf(ARequest.Routine);
  if mQualifier = '' then
  begin
    AHead.Text := mIndent + mHeader + mSignature + TTextLines.LineBreakOf(AText);
    Exit(True);
  end;
  mTypeBody := TRoutineBody.TypeBody(ATree.Root, ClassNameOf(mQualifier));
  if mTypeBody = nil then
  begin
    Exit(Fail(cTexts[TSharedText.ClassNotInTheFile].Fmt([ClassNameOf(mQualifier)]), AHead.Reason));
  end;
  mClassDecl := mHeader + mSignature + IfThen(IsStaticRoutine(ATree.Tokens, ARequest.Routine, ARequest.Body),
    ' static;', '');
  Result := TRoutineBody.MemberDeclaration(AText, ATree, mTypeBody, TMemberEntry.Create('private', mClassDecl),
    ARequest.Style, mEdit);
  if not Result then
  begin
    Exit(Fail(cTexts[TSharedText.ClassDeclarationCannotBeExtended].Text, AHead.Reason));
  end;
  AEdits := AEdits + [mEdit];
  AHead.Text := mIndent + mHeader + mQualifier + '.' + mSignature + TTextLines.LineBreakOf(AText);
end;

{ TExtractSignature }

constructor TExtractSignature.Create(const AText: string; ATree: TSyntaxTree; ARoutine: TSyntaxNode;
  const AOptions: TExtractOptions);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FRoutine := ARoutine;
  FOptions := AOptions;
  FLineBreak := TTextLines.LineBreakOf(AText);
  FIndentUnit := TRoutineBody.IndentUnit(AOptions.Style);
  FIndent := TTextLines.IndentOf(AText, ARoutine.StartPos.Line);
end;

function TExtractSignature.LocalType(const ALocal: TRoutineLocal; out AType: string): Boolean;
var
  mProbed: TProbedType;
begin
  AType := ALocal.TypeText;
  if (AType = '') and (ALocal.Initializer <> nil) then
  begin
    mProbed := TExtractSupport.TypeOfExpression(FText, FTree, ALocal.Initializer, ALocal.Statement, FOptions);
    AType := mProbed.Name;
    TExtractSupport.AddUsesFor(FTree, FText, mProbed, FRoutine.StartOffset, FEdits);
  end;
  Result := AType <> '';
end;

procedure TExtractSignature.AddConstant(const ALocal: TRoutineLocal);
begin
  FConstLines := FConstLines + FIndent + FIndentUnit + TRoutineBody.TextOf(FText, ALocal.Decl) + FLineBreak;
end;

procedure TExtractSignature.AddVariable(const AName, AType: string);
begin
  FVarLines := FVarLines + FIndent + FIndentUnit + AName + ': ' + AType + ';' + FLineBreak;
end;

procedure TExtractSignature.AddParameter(const AModifier, AName, AType: string);
begin
  if FParams <> '' then
  begin
    FParams := FParams + '; ';
    FArgs := FArgs + ', ';
  end;
  FParams := FParams + AModifier + AName + ': ' + AType;
  FArgs := FArgs + AName;
end;

function TExtractSignature.ParamsText: string;
begin
  Result := '';
  if FParams <> '' then
  begin
    Result := '(' + FParams + ')';
  end;
end;

function TExtractSignature.ArgsText: string;
begin
  Result := '';
  if FArgs <> '' then
  begin
    Result := '(' + FArgs + ')';
  end;
end;

function TExtractSignature.Declarations: string;
begin
  Result := '';
  if FVarLines <> '' then
  begin
    Result := Result + FIndent + 'var' + FLineBreak + FVarLines;
  end;
  if FConstLines <> '' then
  begin
    Result := Result + FIndent + 'const' + FLineBreak + FConstLines;
  end;
end;

function TExtractSignature.Key(const AHead: string): string;
begin
  Result := AHead + Declarations;
end;

function TExtractSignature.RoutineText(const AHead, ABody, ABodyIndent: string): string;
begin
  Result := AHead + Declarations + FIndent + 'begin' + FLineBreak + TRoutineBody.Reindent(ABody, ABodyIndent,
    FIndent + FIndentUnit, FLineBreak) + FLineBreak + FIndent + 'end;' + FLineBreak + FLineBreak;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.Extract.Shared', cTexts);

end.
