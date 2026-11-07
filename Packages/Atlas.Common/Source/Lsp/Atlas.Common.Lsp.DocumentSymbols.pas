unit Atlas.Common.Lsp.DocumentSymbols;

// Gliederung einer Datei für textDocument/documentSymbol: hierarchische
// DocumentSymbol-Liste aus dem Syntaxbaum. Die Wurzel ist die Unit (bzw. das
// Programm), darunter interface und implementation, darunter Typen mit ihren
// Mitgliedern, Konstanten, Variablen und Routinen.
//
// Für das Gliederungsfenster des Plugins (#537) tragen Symbole zusätzlich ein
// Objekt "atlas" (vom LSP nicht vorgesehen, andere Clients übergehen es):
//   - visibility: Sichtbarkeit von Mitgliedern ("private", "strict protected",
//     …). Ohne Angabe gilt bei Klassen mit Vorfahr (außer TObject,
//     TInterfacedObject und Ausnahmen) "published" wie bei {$M+}-Klassen
//     (Formulare, Komponenten), sonst "public".
//   - classMember, override, virtual, abstract: nur wenn wahr.
//   - unimplemented: deklarierte Methode ohne Rumpf (#124, TClassCompletion).
//   - condition: Bedingung des aktiven {$IFDEF}-Zweigs, in dem das Symbol steht
//     (nur das äußerste Symbol im Zweig) oder in dem der Rumpf einer Routine
//     steht (#845), z. B. "CPUX64".
//
// Variante Teile eines Records (#846): ein benanntes Selektorfeld steht wie die
// übrigen Felder im Record, die Zweige bilden eine Gruppe "case Integer of"
// (SymbolKind Namespace) mit allen ihren Feldern; ein verschachtelter Teil ist
// eine eigene Gruppe darin.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Semantics.TypeInfoClasses;

type
  TLspDocumentSymbols = class
  public const
    cMethod = 'textDocument/documentSymbol';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FReadText: TTypeInfoReadText;
    function HandleDocumentSymbol(const AParams: TJSONValue;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore);
    /// <summary>Registriert die Anfrage am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Gliederung des Baums. Der Aufrufer übernimmt das Array.</summary>
    class function BuildSymbols(ATree: TSyntaxTree): TJSONArray; overload; static;
    /// <summary>Wie oben; markiert zusätzlich deklarierte Methoden ohne Rumpf (#124, #537) aus AText.</summary>
    class function BuildSymbols(ATree: TSyntaxTree; const AText: string): TJSONArray; overload; static;
    /// <summary>Wie oben; die Standardsichtbarkeit (published bei {$M+}-Klassen, #537) folgt den Vorfahren über
    /// AIndex und liest deren Dateien mit AReadText (beide dürfen nil sein).</summary>
    class function BuildSymbols(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
      const AReadText: TTypeInfoReadText): TJSONArray; overload; static;
    /// <summary>Wie oben; AConditionals sind die Zweige der Datei für atlas.condition (#845).</summary>
    class function BuildSymbols(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
      const AReadText: TTypeInfoReadText; const AConditionals: TArray<TConditionalRange>): TJSONArray;
      overload; static;
    /// <summary>Symbolindex für die Vorfahren (#537); ohne gelten nur die bekannten Klassen der RTL/VCL/FMX.</summary>
    property Index: ISymbolIndex read FIndex write FIndex;
    /// <summary>Liest die Datei eines Vorfahren aus dem Index.</summary>
    property ReadText: TTypeInfoReadText read FReadText write FReadText;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Lsp.FormFiles,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDocumentSymbolsText = (FieldTextDocumentUriMissingIn);

const
  cTexts: array[TDocumentSymbolsText] of TAtlasText = (
    (De: 'Feld "textDocument.uri" fehlt in '; En: 'Field "textDocument.uri" missing in '));

{$SCOPEDENUMS OFF}

type
  /// <summary>Baut die Symbole; kennt die Token für Namensbereiche und Routinenarten.</summary>
  TSymbolBuilder = class
  private
    FTokens: TArray<TPascalToken>;
    /// <summary>Aktuelle Sichtbarkeit in einem Typ; '' außerhalb.</summary>
    FVisibility: string;
    /// <summary>Namensanfang deklarierter Methoden ohne Rumpf (#124).</summary>
    FUnimplemented: TArray<TTextPosition>;
    /// <summary>Aktive Token (ohne inaktive Zweige) für den Schalter {$M+}.</summary>
    FActive: TArray<TPascalToken>;
    FTypeInfo: TTypeInfoClasses;
    /// <summary>Klassen dieser Datei: mit RTTI für published übersetzt?</summary>
    FLocalTypeInfo: TDictionary<string, Boolean>;
    /// <summary>Nur die aktiven Zweige (#845).</summary>
    FConditionals: TArray<TConditionalRange>;
    function IsClassMember(ANode: TSyntaxNode): Boolean;
    function InnermostBranch(const APosition: TTextPosition): Integer;
    function ConditionOf(ANode: TSyntaxNode): string;
    procedure AddExtras(ASymbol: TJSONObject; ANode: TSyntaxNode; ARoutine: Boolean);
    /// <summary>override, virtual (auch für dynamic) und abstract der Routine ANode nach AExtras.</summary>
    procedure AddRoutineFlags(AExtras: TJSONObject; ANode: TSyntaxNode);
    /// <summary>Deklarierte Methode ANode ohne Rumpf (#124)?</summary>
    function IsUnimplemented(ANode: TSyntaxNode): Boolean;
    /// <summary>Wird AAncestor mit RTTI für published übersetzt (Index, sonst die bekannten Klassen)?</summary>
    function AncestorHasTypeInfo(const AAncestor: string): Boolean;
    /// <summary>Hat der Vorfahr des Klassenrumpfs ABody RTTI für published? False ohne Vorfahr.</summary>
    function InheritsTypeInfo(ABody: TSyntaxNode): Boolean;
    function DefaultVisibility(ADecl, ABody: TSyntaxNode): string;
    function TokenIndexAt(AOffset: Integer): Integer;
    function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
    function NewSymbol(ANode: TSyntaxNode; const AName: string; AKind: Integer;
      const ADetail: string): TJSONObject; overload;
    function NewSymbol(ANode: TSyntaxNode; const AName: string; AKind: Integer): TJSONObject; overload;
    procedure AddChild(ASymbol, AChild: TJSONObject);
    function RoutineKind(ANode: TSyntaxNode; AInType: Boolean): Integer;
    function TypeSymbol(ADecl: TSyntaxNode): TJSONObject;
    /// <summary>Mitglieder des Rumpfs ABody (Typ ADecl) unter ASymbol.</summary>
    procedure AddTypeMembers(ASymbol: TJSONObject; ADecl, ABody: TSyntaxNode);
    /// <summary>Konstante oder Property ANode der Art AKind; in einem Typ mit Sichtbarkeit.</summary>
    procedure AddMember(ANode: TSyntaxNode; ATarget: TJSONArray; AKind: Integer; AInType: Boolean);
    /// <summary>Routine ANode samt lokalen Routinen, Typen und Konstanten.</summary>
    procedure AddRoutine(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
    procedure AddDeclarations(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
    procedure AddDeclaration(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
    procedure MoveChildren(ASource: TJSONArray; ATarget: TJSONObject);
    procedure AddNames(ANode: TSyntaxNode; ATarget: TJSONArray; AKind: Integer);
    procedure AddVariantPart(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
  public
    constructor Create(const ATokens: TArray<TPascalToken>; const AUnimplemented: TArray<TTextPosition>);
      overload;
    /// <summary>AActive: aktive Token für {$M+}; ATypeInfo gehört weiter dem Aufrufer.</summary>
    constructor Create(const ATokens: TArray<TPascalToken>; const AUnimplemented: TArray<TTextPosition>;
      const AActive: TArray<TPascalToken>; ATypeInfo: TTypeInfoClasses); overload;
    destructor Destroy; override;
    /// <summary>Zweige der Datei; inaktive werden übergangen.</summary>
    procedure SetConditionals(const AConditionals: TArray<TConditionalRange>);
    function Build(ARoot: TSyntaxNode): TJSONArray;
  end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

{ TSymbolBuilder }

constructor TSymbolBuilder.Create(const ATokens: TArray<TPascalToken>;
  const AUnimplemented: TArray<TTextPosition>);
begin
  Create(ATokens, AUnimplemented, ATokens, nil);
end;

constructor TSymbolBuilder.Create(const ATokens: TArray<TPascalToken>; const AUnimplemented: TArray<TTextPosition>;
  const AActive: TArray<TPascalToken>; ATypeInfo: TTypeInfoClasses);
begin
  inherited Create;
  FTokens := ATokens;
  FUnimplemented := AUnimplemented;
  FActive := AActive;
  FTypeInfo := ATypeInfo;
  FLocalTypeInfo := TDictionary<string, Boolean>.Create;
end;

destructor TSymbolBuilder.Destroy;
begin
  FLocalTypeInfo.Free;
  inherited Destroy;
end;

procedure TSymbolBuilder.SetConditionals(const AConditionals: TArray<TConditionalRange>);
var
  mConditional: TConditionalRange;
begin
  FConditionals := nil;
  for mConditional in AConditionals do
  begin
    if mConditional.Active and (mConditional.Condition <> '') then
    begin
      FConditionals := FConditionals + [mConditional];
    end;
  end;
end;

/// <summary>A vor B?</summary>
function PositionBefore(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

/// <summary>Liegt APosition in ARange (Ende ausgeschlossen)?</summary>
function PositionIn(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := not PositionBefore(APosition, ARange.StartPos) and PositionBefore(APosition, ARange.EndPos);
end;

function TSymbolBuilder.InnermostBranch(const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  // Verschachtelte Zweige beginnen später als die äußeren.
  Result := -1;
  for mIndex := 0 to High(FConditionals) do
  begin
    if PositionIn(APosition, FConditionals[mIndex].Range) and ((Result < 0) or
      PositionBefore(FConditionals[Result].Range.StartPos, FConditionals[mIndex].Range.StartPos)) then
    begin
      Result := mIndex;
    end;
  end;
end;

function TSymbolBuilder.ConditionOf(ANode: TSyntaxNode): string;
var
  mBranch: Integer;
  mBody: TSyntaxNode;
begin
  Result := '';
  if FConditionals = nil then
  begin
    Exit;
  end;
  // Das Symbol steht im Zweig; liegt der Elternknoten im selben Zweig, trägt ihn schon jener.
  mBranch := InnermostBranch(ANode.StartPos);
  if (mBranch >= 0) and ((ANode.Parent = nil) or not PositionIn(ANode.Parent.StartPos,
    FConditionals[mBranch].Range)) then
  begin
    Exit(FConditionals[mBranch].Condition);
  end;
  // Nur der Rumpf steht im Zweig: begin … end bzw. asm … end je Plattform (Fälle 01 und 10).
  if ANode.Kind <> TSyntaxKind.RoutineDecl then
  begin
    Exit;
  end;
  mBody := ANode.FindChild(TSyntaxKind.Block);
  if mBody = nil then
  begin
    mBody := ANode.FindChild(TSyntaxKind.AsmBlock);
  end;
  if mBody = nil then
  begin
    Exit;
  end;
  mBranch := InnermostBranch(mBody.StartPos);
  if (mBranch >= 0) and not PositionIn(ANode.StartPos, FConditionals[mBranch].Range) then
  begin
    Result := FConditionals[mBranch].Condition;
  end;
end;

function TSymbolBuilder.IsClassMember(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  // "class procedure", "class function": class steht vorn; bei "class property" und "class var" hat der
  // Parser das Wort schon übersprungen, es steht also davor.
  mIndex := TokenIndexAt(ANode.StartOffset);
  while (mIndex < Length(FTokens)) and (FTokens[mIndex].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(mIndex);
  end;
  if (mIndex < Length(FTokens)) and FTokens[mIndex].IsKeyword('class') then
  begin
    Exit(True);
  end;
  Dec(mIndex);
  while (mIndex >= 0) and (FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(mIndex);
  end;
  Result := (mIndex >= 0) and FTokens[mIndex].IsKeyword('class');
end;

function TSymbolBuilder.AncestorHasTypeInfo(const AAncestor: string): Boolean;
begin
  if FTypeInfo <> nil then
  begin
    Result := FTypeInfo.HasTypeInfo(AAncestor);
  end
  else
  begin
    Result := TTypeInfoClasses.KnownTypeInfoClass(AAncestor);
  end;
end;

function TSymbolBuilder.InheritsTypeInfo(ABody: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mAncestor: string;
begin
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if (ABody[mIndex].Kind = TSyntaxKind.TypeReference) and (ABody[mIndex].Name <> '') then
    begin
      // Nur der erste Eintrag ist der Vorfahr, die übrigen sind Interfaces.
      mAncestor := ABody[mIndex].Name;
      if not FLocalTypeInfo.TryGetValue(LowerCase(Copy(mAncestor, LastDelimiter('.', mAncestor) + 1, MaxInt)),
        Result) then
      begin
        Result := AncestorHasTypeInfo(mAncestor);
      end;
      Exit;
    end;
  end;
  Result := False;
end;

function TSymbolBuilder.DefaultVisibility(ADecl, ABody: TSyntaxNode): string;
var
  mTypeInfo: Boolean;
begin
  Result := 'public';
  if not (ABody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType]) then
  begin
    Exit;
  end;
  // Ohne Angabe sind Mitglieder published, wenn die Klasse mit RTTI für published übersetzt wird: {$M+} bzw.
  // {$TYPEINFO ON} bei der Deklaration oder ein so übersetzter Vorfahr (TPersistent und Nachfahren).
  mTypeInfo := TTypeInfoClasses.SwitchAt(FActive, ADecl.StartPos) or InheritsTypeInfo(ABody);
  FLocalTypeInfo.AddOrSetValue(LowerCase(ADecl.Name), mTypeInfo);
  if mTypeInfo then
  begin
    Result := 'published';
  end;
end;

procedure TSymbolBuilder.AddRoutineFlags(AExtras: TJSONObject; ANode: TSyntaxNode);
var
  mIndex: Integer;
  mDirective: string;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind <> TSyntaxKind.Directive then
    begin
      Continue;
    end;
    mDirective := ANode[mIndex].Name;
    // dynamic ist virtuell wie virtual.
    if mDirective = 'dynamic' then
    begin
      mDirective := 'virtual';
    end;
    if ((mDirective = 'override') or (mDirective = 'virtual') or (mDirective = 'abstract')) and
      (AExtras.GetValue(mDirective) = nil) then
    begin
      AExtras.AddPair(mDirective, TJSONBool.Create(True));
    end;
  end;
end;

function TSymbolBuilder.IsUnimplemented(ANode: TSyntaxNode): Boolean;
var
  mStart, mPosition: TTextPosition;
begin
  mStart := NameRange(ANode, ANode.Name).StartPos;
  for mPosition in FUnimplemented do
  begin
    if (mPosition.Line = mStart.Line) and (mPosition.Character = mStart.Character) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TSymbolBuilder.AddExtras(ASymbol: TJSONObject; ANode: TSyntaxNode; ARoutine: Boolean);
var
  mExisting: TJSONValue;
  mExtras: TJSONObject;
begin
  // NewSymbol legt "atlas" schon an, wenn das Symbol eine Bedingung hat.
  mExisting := ASymbol.GetValue('atlas');
  if mExisting is TJSONObject then
  begin
    mExtras := TJSONObject(mExisting);
  end
  else
  begin
    mExtras := TJSONObject.Create;
  end;
  if FVisibility <> '' then
  begin
    mExtras.AddPair('visibility', FVisibility);
  end;
  if IsClassMember(ANode) then
  begin
    mExtras.AddPair('classMember', TJSONBool.Create(True));
  end;
  if ARoutine then
  begin
    AddRoutineFlags(mExtras, ANode);
    if IsUnimplemented(ANode) then
    begin
      mExtras.AddPair('unimplemented', TJSONBool.Create(True));
    end;
  end;
  if mExtras = mExisting then
  begin
    Exit;
  end;
  if mExtras.Count > 0 then
  begin
    ASymbol.AddPair('atlas', mExtras);
  end
  else
  begin
    mExtras.Free;
  end;
end;

function TSymbolBuilder.TokenIndexAt(AOffset: Integer): Integer;
var
  mLeft: Integer;
  mRight: Integer;
  mMiddle: Integer;
begin
  // Erstes Token mit Offset >= AOffset (binäre Suche), sonst Length(FTokens).
  mLeft := 0;
  mRight := Length(FTokens);
  while mLeft < mRight do
  begin
    mMiddle := (mLeft + mRight) div 2;
    if FTokens[mMiddle].Offset < AOffset then
    begin
      mLeft := mMiddle + 1;
    end
    else
    begin
      mRight := mMiddle;
    end;
  end;
  Result := mLeft;
end;

function TSymbolBuilder.NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
var
  mIndex: Integer;
  mSimple: string;
begin
  // Bei TFoo.Bar zeigt die Auswahl auf Bar.
  mSimple := AName;
  if mSimple.LastIndexOf('.') >= 0 then
  begin
    mSimple := mSimple.Substring(mSimple.LastIndexOf('.') + 1);
  end;
  mIndex := TokenIndexAt(ANode.StartOffset);
  while (mIndex < Length(FTokens)) and (FTokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      (SameText(FTokens[mIndex].Text, mSimple) or SameText(FTokens[mIndex].Text, '&' + mSimple)) then
    begin
      Exit(TTextRange.Create(FTokens[mIndex].StartPos, FTokens[mIndex].EndPos));
    end;
    Inc(mIndex);
  end;
  Result := NodeRange(ANode);
end;

function TSymbolBuilder.NewSymbol(ANode: TSyntaxNode; const AName: string; AKind: Integer): TJSONObject;
begin
  Result := NewSymbol(ANode, AName, AKind, '');
end;

function TSymbolBuilder.NewSymbol(ANode: TSyntaxNode; const AName: string; AKind: Integer;
  const ADetail: string): TJSONObject;
var
  mCondition, mName: string;
begin
  Result := TJSONObject.Create;
  // Namen ohne Escape-& wie im Index: &begin heißt begin, &&op_Equality heißt &op_Equality (#1137).
  mName := TPascalLexer.PlainName(AName);
  // VS Code lehnt Symbole mit leerem Namen ab.
  if mName = '' then
  begin
    Result.AddPair('name', '?');
  end
  else
  begin
    Result.AddPair('name', mName);
  end;
  if ADetail <> '' then
  begin
    Result.AddPair('detail', ADetail);
  end;
  Result.AddPair('kind', TJSONNumber.Create(AKind));
  Result.AddPair('range', TLspPositions.RangeToJson(NodeRange(ANode)));
  Result.AddPair('selectionRange', TLspPositions.RangeToJson(NameRange(ANode, mName)));
  mCondition := ConditionOf(ANode);
  if mCondition <> '' then
  begin
    Result.AddPair('atlas', TJSONObject.Create(TJSONPair.Create('condition', mCondition)));
  end;
end;

procedure TSymbolBuilder.AddChild(ASymbol, AChild: TJSONObject);
var
  mChildren: TJSONArray;
begin
  mChildren := ASymbol.GetValue('children') as TJSONArray;
  if mChildren = nil then
  begin
    mChildren := TJSONArray.Create;
    ASymbol.AddPair('children', mChildren);
  end;
  mChildren.AddElement(AChild);
end;

function TSymbolBuilder.RoutineKind(ANode: TSyntaxNode; AInType: Boolean): Integer;
var
  mIndex: Integer;
begin
  mIndex := TokenIndexAt(ANode.StartOffset);
  // class procedure, class function ...: das Wort nach class zählt.
  while (mIndex < Length(FTokens)) and (FTokens[mIndex].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(mIndex);
  end;
  if (mIndex < Length(FTokens)) and FTokens[mIndex].IsKeyword('class') then
  begin
    Inc(mIndex);
  end;
  if (mIndex < Length(FTokens)) and (FTokens[mIndex].IsKeyword('constructor') or FTokens[mIndex].IsKeyword('destructor')) then
  begin
    Result := TLspSymbolKind.cConstructor_;
  end
  else if AInType or (ANode.Name.IndexOf('.') >= 0) then
  begin
    Result := TLspSymbolKind.cMethod;
  end
  else
  begin
    Result := TLspSymbolKind.cFunction_;
  end;
end;

/// <summary>Rumpf der Typdeklaration ADecl (ohne generische Parameter und Attribute); nil ohne.</summary>
function TypeBody(ADecl: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if not (ADecl[mIndex].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
    begin
      Exit(ADecl[mIndex]);
    end;
  end;
  Result := nil;
end;

/// <summary>Symbolart und Detail ("class", "record" …) zum Rumpf ABody (nil = unbekannt).</summary>
function TypeKindOf(ABody: TSyntaxNode; out ADetail: string): Integer;
begin
  Result := TLspSymbolKind.cTypeParameter;
  ADetail := '';
  if ABody = nil then
  begin
    Exit;
  end;
  case ABody.Kind of
    TSyntaxKind.ClassType, TSyntaxKind.ClassOfType, TSyntaxKind.ForwardType:
      begin
        Result := TLspSymbolKind.cClass_;
        ADetail := 'class';
      end;
    TSyntaxKind.ObjectType:
      begin
        Result := TLspSymbolKind.cClass_;
        ADetail := 'object';
      end;
    TSyntaxKind.HelperType:
      begin
        Result := TLspSymbolKind.cClass_;
        ADetail := 'helper';
      end;
    TSyntaxKind.RecordType:
      begin
        Result := TLspSymbolKind.cStruct;
        ADetail := 'record';
      end;
    TSyntaxKind.InterfaceType:
      begin
        Result := TLspSymbolKind.cInterface_;
        ADetail := 'interface';
      end;
    TSyntaxKind.EnumType:
      Result := TLspSymbolKind.cEnum;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TSymbolBuilder.AddTypeMembers(ASymbol: TJSONObject; ADecl, ABody: TSyntaxNode);
var
  mMembers: TJSONArray;
  mOuter: string;
begin
  // Verschachtelte Typen haben eigene Abschnitte; danach gilt wieder der äußere.
  mOuter := FVisibility;
  FVisibility := DefaultVisibility(ADecl, ABody);
  mMembers := TJSONArray.Create;
  try
    AddDeclarations(ABody, mMembers, True);
    MoveChildren(mMembers, ASymbol);
  finally
    mMembers.Free;
    FVisibility := mOuter;
  end;
end;

function TSymbolBuilder.TypeSymbol(ADecl: TSyntaxNode): TJSONObject;
var
  mBody: TSyntaxNode;
  mIndex, mKind: Integer;
  mDetail: string;
begin
  mBody := TypeBody(ADecl);
  mKind := TypeKindOf(mBody, mDetail);
  Result := NewSymbol(ADecl, ADecl.Name, mKind, mDetail);
  if mBody = nil then
  begin
    Exit;
  end;
  if mBody.Kind = TSyntaxKind.EnumType then
  begin
    for mIndex := 0 to mBody.ChildCount - 1 do
    begin
      if mBody[mIndex].Kind = TSyntaxKind.Identifier then
      begin
        AddChild(Result, NewSymbol(mBody[mIndex], mBody[mIndex].Name, TLspSymbolKind.cEnumMember));
      end;
    end;
  end
  else if mBody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType,
    TSyntaxKind.RecordType, TSyntaxKind.InterfaceType] then
  begin
    AddTypeMembers(Result, ADecl, mBody);
  end;
end;

procedure TSymbolBuilder.AddNames(ANode: TSyntaxNode; ATarget: TJSONArray; AKind: Integer);
var
  mName: string;
  mSymbol: TJSONObject;
begin
  // Felder und Variablen mit mehreren Namen: A, B: Integer.
  for mName in ANode.Name.Split([',']) do
  begin
    mSymbol := NewSymbol(ANode, mName.Trim, AKind);
    if AKind = TLspSymbolKind.cField then
    begin
      AddExtras(mSymbol, ANode, False);
    end;
    ATarget.AddElement(mSymbol);
  end;
end;

/// <summary>Typ des Selektors eines varianten Teils: "Integer" bei case Integer of und case Tag: Integer of.</summary>
function SelectorType(AVariant: TSyntaxNode): string;
var
  mIndex, mInner: Integer;
begin
  Result := '';
  for mIndex := 0 to AVariant.ChildCount - 1 do
  begin
    if AVariant[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      Exit(AVariant[mIndex].Name);
    end
    else if AVariant[mIndex].Kind = TSyntaxKind.Field then
    begin
      for mInner := 0 to AVariant[mIndex].ChildCount - 1 do
      begin
        if AVariant[mIndex][mInner].Kind = TSyntaxKind.TypeReference then
        begin
          Exit(AVariant[mIndex][mInner].Name);
        end;
      end;
    end;
  end;
end;

procedure TSymbolBuilder.AddVariantPart(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
var
  mGroup: TJSONObject;
  mFields: TJSONArray;
  mTitle: string;
  mIndex: Integer;
begin
  // case Tag: Typ of (#846): das Selektorfeld neben die Felder des Records, die Zweige in eine Gruppe.
  mTitle := 'case ';
  if ANode.Name <> '' then
  begin
    mTitle := mTitle + ANode.Name + ': ';
  end;
  mTitle := mTitle + SelectorType(ANode) + ' of';
  mFields := TJSONArray.Create;
  try
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind = TSyntaxKind.Field then
      begin
        AddNames(ANode[mIndex], ATarget, TLspSymbolKind.cField);
      end
      else if ANode[mIndex].Kind = TSyntaxKind.CaseItem then
      begin
        AddDeclarations(ANode[mIndex], mFields, AInType);
      end;
    end;
    if mFields.Count = 0 then
    begin
      Exit;
    end;
    mGroup := NewSymbol(ANode, mTitle, TLspSymbolKind.cNamespace);
    ATarget.AddElement(mGroup);
    MoveChildren(mFields, mGroup);
  finally
    mFields.Free;
  end;
end;

procedure TSymbolBuilder.AddDeclarations(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    AddDeclaration(ANode[mIndex], ATarget, AInType);
  end;
end;

procedure TSymbolBuilder.AddMember(ANode: TSyntaxNode; ATarget: TJSONArray; AKind: Integer; AInType: Boolean);
var
  mSymbol: TJSONObject;
begin
  mSymbol := NewSymbol(ANode, ANode.Name, AKind);
  if AInType then
  begin
    AddExtras(mSymbol, ANode, False);
  end;
  ATarget.AddElement(mSymbol);
end;

procedure TSymbolBuilder.AddRoutine(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
var
  mSymbol: TJSONObject;
  mNested: TJSONArray;
  mIndex: Integer;
  mOuter: string;
begin
  mSymbol := NewSymbol(ANode, ANode.Name, RoutineKind(ANode, AInType));
  ATarget.AddElement(mSymbol);
  // Lokale Routinen, Typen und Konstanten unter der Routine. Der eigene
  // Kopf ist ebenfalls ein Kind und darf nicht noch einmal erscheinen.
  // Sie liegen außerhalb jedes Typs: keine Sichtbarkeit.
  mOuter := FVisibility;
  FVisibility := '';
  mNested := TJSONArray.Create;
  try
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind <> TSyntaxKind.RoutineHeader then
      begin
        AddDeclaration(ANode[mIndex], mNested, False);
      end;
    end;
    MoveChildren(mNested, mSymbol);
  finally
    mNested.Free;
    FVisibility := mOuter;
  end;
end;

procedure TSymbolBuilder.AddDeclaration(ANode: TSyntaxNode; ATarget: TJSONArray; AInType: Boolean);
var
  mSymbol: TJSONObject;
begin
  case ANode.Kind of
    TSyntaxKind.Visibility:
      if AInType then
      begin
        FVisibility := ANode.Name;
      end;
    TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
      AddDeclarations(ANode, ATarget, AInType);
    TSyntaxKind.VariantPart:
      AddVariantPart(ANode, ATarget, AInType);
    TSyntaxKind.TypeDecl:
      ATarget.AddElement(TypeSymbol(ANode));
    TSyntaxKind.ConstDecl:
      AddMember(ANode, ATarget, TLspSymbolKind.cConstant, AInType);
    TSyntaxKind.VarDecl:
      if AInType then
      begin
        AddNames(ANode, ATarget, TLspSymbolKind.cField);
      end
      else
      begin
        AddNames(ANode, ATarget, TLspSymbolKind.cVariable);
      end;
    TSyntaxKind.Field:
      AddNames(ANode, ATarget, TLspSymbolKind.cField);
    TSyntaxKind.PropertyDecl:
      AddMember(ANode, ATarget, TLspSymbolKind.cProperty_, AInType);
    TSyntaxKind.RoutineHeader:
      // Methodenzuordnung procedure IFoo.Bar = MyBar erscheint nicht in der Gliederung (#849).
      if not ANode.IsMethodResolution then
      begin
        mSymbol := NewSymbol(ANode, ANode.Name, RoutineKind(ANode, AInType));
        if AInType then
        begin
          AddExtras(mSymbol, ANode, True);
        end;
        ATarget.AddElement(mSymbol);
      end;
    TSyntaxKind.RoutineDecl:
      AddRoutine(ANode, ATarget, AInType);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TSymbolBuilder.MoveChildren(ASource: TJSONArray; ATarget: TJSONObject);
begin
  while ASource.Count > 0 do
  begin
    AddChild(ATarget, TJSONObject(ASource.Remove(0)));
  end;
end;

function TSymbolBuilder.Build(ARoot: TSyntaxNode): TJSONArray;
var
  mRoot: TJSONObject;
  mSection: TJSONObject;
  mItems: TJSONArray;
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := TJSONArray.Create;
  mRoot := NewSymbol(ARoot, ARoot.Name, TLspSymbolKind.cModule);
  Result.AddElement(mRoot);
  mItems := TJSONArray.Create;
  try
    for mIndex := 0 to ARoot.ChildCount - 1 do
    begin
      mChild := ARoot[mIndex];
      if mChild.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      begin
        if mChild.Kind = TSyntaxKind.InterfaceSection then
        begin
          mSection := NewSymbol(mChild, 'interface', TLspSymbolKind.cNamespace);
        end
        else
        begin
          mSection := NewSymbol(mChild, 'implementation', TLspSymbolKind.cNamespace);
        end;
        AddChild(mRoot, mSection);
        AddDeclarations(mChild, mItems, False);
        MoveChildren(mItems, mSection);
      end
      else
      begin
        // program, library, package: Deklarationen direkt unter der Wurzel.
        AddDeclaration(mChild, mItems, False);
        MoveChildren(mItems, mRoot);
      end;
    end;
  finally
    mItems.Free;
  end;
end;

{ TLspDocumentSymbols }

constructor TLspDocumentSymbols.Create(const AStore: IDocumentStore);
begin
  inherited Create;
  FStore := AStore;
end;

procedure TLspDocumentSymbols.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Nebenläufig: Parsen großer Dateien blockiert die Nachrichtenschleife nicht.
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleDocumentSymbol);
end;

class function TLspDocumentSymbols.BuildSymbols(ATree: TSyntaxTree): TJSONArray;
var
  mBuilder: TSymbolBuilder;
begin
  mBuilder := TSymbolBuilder.Create(ATree.Tokens, nil);
  try
    Result := mBuilder.Build(ATree.Root);
  finally
    mBuilder.Free;
  end;
end;

class function TLspDocumentSymbols.BuildSymbols(ATree: TSyntaxTree; const AText: string): TJSONArray;
begin
  Result := BuildSymbols(ATree, AText, nil, nil);
end;

class function TLspDocumentSymbols.BuildSymbols(ATree: TSyntaxTree; const AText: string;
  const AIndex: ISymbolIndex; const AReadText: TTypeInfoReadText): TJSONArray;
begin
  Result := BuildSymbols(ATree, AText, AIndex, AReadText, nil);
end;

class function TLspDocumentSymbols.BuildSymbols(ATree: TSyntaxTree; const AText: string;
  const AIndex: ISymbolIndex; const AReadText: TTypeInfoReadText;
  const AConditionals: TArray<TConditionalRange>): TJSONArray;
var
  mBuilder: TSymbolBuilder;
  mMissing: TArray<TTextPosition>;
  mMethod: TUnmatchedMethod;
  mTypeInfo: TTypeInfoClasses;
begin
  mMissing := nil;
  for mMethod in TClassCompletion.Unmatched(ATree, AText) do
  begin
    if mMethod.Declared then
    begin
      mMissing := mMissing + [mMethod.Symbol.SelectionRange.StartPos];
    end;
  end;
  mTypeInfo := TTypeInfoClasses.Create(AIndex, AReadText);
  try
    mBuilder := TSymbolBuilder.Create(ATree.Tokens, mMissing, TTypeInfoClasses.ActiveTokens(AText), mTypeInfo);
    try
      mBuilder.SetConditionals(AConditionals);
      Result := mBuilder.Build(ATree.Root);
    finally
      mBuilder.Free;
    end;
  finally
    mTypeInfo.Free;
  end;
end;

function TLspDocumentSymbols.HandleDocumentSymbol(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mForm: TDfmDocument;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TDocumentSymbolsText.FieldTextDocumentUriMissingIn].Text + cMethod);
  end;
  // Nicht geöffnete Dokumente haben keine Gliederung.
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  // Formulardateien (#44) haben einen eigenen Baum.
  if TDfmParser.IsFormFile(mUri) then
  begin
    mForm := TDfmParser.Parse(mDocument.Text);
    try
      Exit(TLspFormFiles.BuildSymbols(mForm));
    finally
      mForm.Free;
    end;
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mTree := mShared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Result := BuildSymbols(mTree, mDocument.Text, FIndex, FReadText, mShared.Conditionals);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.DocumentSymbols', cTexts);

end.
