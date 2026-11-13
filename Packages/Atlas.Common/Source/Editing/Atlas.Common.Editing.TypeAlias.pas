unit Atlas.Common.Editing.TypeAlias;

// Typ-Alias einführen und auflösen (#681):
//   - Targets: Typausdrücke an einer Stelle, für die ein Alias lohnt
//     (generische Typen mit Argumenten, Arrays, Mengen, Methodenreferenzen
//     und prozedurale Typen), der äußere zuerst; mit Namensvorschlag aus
//     dem Zusammenhang (Feld FGroups mit TList<TKunde> -> TKundeGroups).
//     Offene generische Parameter (TList<T> in TBox<T>) ergeben keinen
//     Alias, Delphi kennt keine generischen Aliase; OpenParams nennt sie.
//   - Introduce: schreibt "TName = Ausdruck;" in den type-Abschnitt vor der
//     ersten Verwendung (bei Bedarf mit Vorwärtsdeklaration der eigenen
//     Klasse), im Projekt immer in den interface-Teil, und ersetzt die
//     Stelle, alle gleichen Ausdrücke der Unit oder des Projekts. Gleich
//     heißt: gleiche aufgelöste Typen (TTypeAliasLookup.Key), nicht gleicher
//     Text. Andere Units nur, wenn sie die Unit einbinden.
//   - InlineAlias: ersetzt die Verwendungen eines Alias X = Y durch Y und
//     entfernt ihn, wenn keine bleibt. Ohne Typnamen (Array, Menge,
//     prozeduraler Typ) nur dort, wo Delphi einen Typausdruck annimmt
//     (Feld, Variable, Konstante, Typdeklaration, Element eines Arrays);
//     Parameter, Ergebnisse, Properties, Typargumente und Ausdrücke behalten
//     den Alias. X = type Y ist ein eigener Typ und wird nicht aufgelöst.
// Atlas schreibt immer die zuweisungsverträgliche Form X = Y.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Was ersetzt wird: nur die Stelle, alle gleichen Ausdrücke der Unit oder des Projekts.</summary>
  TTypeAliasScope = (Here, InUnit, Project);

  /// <summary>Schlüssel des Typnamens an ANode (TypeReference, ohne Typargumente) in ATree der Datei AFileName:
  /// Unit und Name des aufgelösten Typs; '' = unbekannt, dann zählt der Name.</summary>
  TTypeKeyFunc = reference to function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode): string;
  /// <summary>Ist AName an AOffset in ATree schon sichtbar vergeben?</summary>
  TTypeNameTakenFunc = reference to function(ATree: TSyntaxTree; const AFileName, AName: string;
    AOffset: Integer): Boolean;
  /// <summary>Unit, die den Typnamen an ANode deklariert; '' = eingebaut oder unbekannt. AImplementation: nur im
  /// implementation-Teil dieser Unit deklariert.</summary>
  TTypeUnitFunc = reference to function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
    out AImplementation: Boolean): string;

  TTypeAliasLookup = record
    Key: TTypeKeyFunc;
    NameTaken: TTypeNameTakenFunc;
    UnitOf: TTypeUnitFunc;
    /// <summary>Nur aus dem Baum: Schlüssel ist der letzte Teil des Namens, vergeben ist ein in der Unit
    /// deklarierter Name, Units unbekannt.</summary>
    class function FromTree: TTypeAliasLookup; static;
  end;

  TTypeAliasTarget = record
    StartOffset: Integer;
    EndOffset: Integer;
    Range: TTextRange;
    /// <summary>Der Ausdruck wie im Quelltext.</summary>
    TypeText: string;
    Kind: TSyntaxKind;
    /// <summary>Vorgeschlagener Name, in der Unit noch frei.</summary>
    Suggestion: string;
    /// <summary>Generische Parameter, die der Ausdruck nutzt, durch Komma getrennt; '' = keine.</summary>
    OpenParams: string;
  end;

  /// <summary>Eine Datei; Offsets nur beim Auflösen: Anfang jeder Verwendung des Alias (0-basiert).</summary>
  TTypeAliasSource = record
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    Offsets: TArray<Integer>;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree): TTypeAliasSource; overload; static;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree;
      const AOffsets: TArray<Integer>): TTypeAliasSource; overload; static;
  end;

  TTypeAliasFileEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  TTypeAliasResult = record
    Files: TArray<TTypeAliasFileEdits>;
    Warnings: TArray<string>;
    /// <summary>Ersetzte Stellen.</summary>
    Places: Integer;
    /// <summary>Was geschieht, dazu je Stelle "Datei, Zeile n".</summary>
    Preview: string;
  end;

  /// <summary>Ein Alias X = Y, der sich auflösen lässt.</summary>
  TInlineAliasTarget = record
    Name: string;
    TypeText: string;
    Kind: TSyntaxKind;
    NamePosition: TTextPosition;
  end;

  /// <summary>Was Introduce einführt: Alias Name für den Ausdruck, der an Position beginnt, mit Reichweite Scope.
  /// </summary>
  TTypeAliasRequest = record
    Position: TTextPosition;
    Name: string;
    Scope: TTypeAliasScope;
    Lookup: TTypeAliasLookup;
    class function Create(const APosition: TTextPosition; const AName: string; AScope: TTypeAliasScope;
      const ALookup: TTypeAliasLookup): TTypeAliasRequest; static;
  end;

  TTypeAlias = class
  public
    class function IntroduceTitle: string; static;
    class function HereTitle: string; static;
    class function UnitTitle: string; static;
    class function ProjectTitle: string; static;
    class function InlineTitle: string; static;
    /// <summary>Grund bei offenen generischen Parametern (%s: die Parameter).</summary>
    class function OpenParamsReason: string; static;
    class function CompatibilityNote: string; static;
    /// <summary>Typausdrücke an APosition, für die ein Alias lohnt: der äußere zuerst, dann der innerste, wenn
    /// er ein anderer ist. Leer ohne Treffer.</summary>
    class function Targets(const AText: string; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; const ALookup: TTypeAliasLookup): TArray<TTypeAliasTarget>; static;
    /// <summary>Schlüssel für die Gleichheit von Typausdrücken: aufgelöste Namen, Typargumente und der Text der
    /// übrigen Teile ohne Groß-/Kleinschreibung und Kommentare.</summary>
    class function KeyOf(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
      const ALookup: TTypeAliasLookup): string; static;
    /// <summary>Alias ARequest.Name für den Ausdruck, der an ARequest.Position beginnt (aus Targets), in
    /// ADeclaring; im Projekt auch gleiche Ausdrücke in AOthers. False mit Grund, wenn es nicht geht.</summary>
    class function Introduce(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
      const ARequest: TTypeAliasRequest; out AResult: TTypeAliasResult; out AReason: string): Boolean; static;
    /// <summary>Alias X = Y, dessen Name in der Deklaration APosition enthält.</summary>
    class function InlineTarget(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      out ATarget: TInlineAliasTarget; out AReason: string): Boolean; static;
    /// <summary>Löst den Alias an APosition (Name in der Deklaration in ADeclaring) auf; die Verwendungen stehen in
    /// den Offsets von ADeclaring und AOthers.</summary>
    class function InlineAlias(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
      const APosition: TTextPosition; const ALookup: TTypeAliasLookup; out AResult: TTypeAliasResult;
      out AReason: string): Boolean; static;
    /// <summary>Name der Reichweite für Befehlsargumente und Einstellungen: here, unit, project.</summary>
    class function ScopeName(AScope: TTypeAliasScope): string; static;
    class function ScopeOf(const AName: string; out AScope: TTypeAliasScope): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.TypeAlias.Texts,
  Atlas.Common.Editing.TypeAlias.Names;

class function TTypeAlias.IntroduceTitle: string;
begin
  Result := cTexts[TEditingTypeAliasText.IntroduceTypeAlias].Text;
end;

class function TTypeAlias.HereTitle: string;
begin
  Result := cTexts[TEditingTypeAliasText.IntroduceTypeAliasThisPlace].Text;
end;

class function TTypeAlias.UnitTitle: string;
begin
  Result := cTexts[TEditingTypeAliasText.IntroduceTypeAliasInThe].Text;
end;

class function TTypeAlias.ProjectTitle: string;
begin
  Result := cTexts[TEditingTypeAliasText.IntroduceTypeAliasInThe2].Text;
end;

class function TTypeAlias.InlineTitle: string;
begin
  Result := cTexts[TEditingTypeAliasText.ResolveAlias].Text;
end;

class function TTypeAlias.OpenParamsReason: string;
begin
  Result := cTexts[TEditingTypeAliasText.NoTypeAliasTheExpression].Text;
end;

class function TTypeAlias.CompatibilityNote: string;
begin
  Result := cTexts[TEditingTypeAliasText.AtlasWritesXYAssignment].Text;
end;

const
  /// <summary>Stellen, an denen ein Typausdruck ohne Typnamen stehen darf.</summary>
  cAnonymousContexts = [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl,
    TSyntaxKind.InlineConst, TSyntaxKind.TypeDecl, TSyntaxKind.ArrayType];

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function Where(const AFileName: string; ALine: Integer): string;
begin
  Result := cTexts[TEditingTypeAliasText.Line].Fmt([ExtractFileName(AFileName), ALine + 1]);
end;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Tiefster Knoten, der AOffset enthält.</summary>
function NodeAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := ANode;
  repeat
    mFound := False;
    for mIndex := 0 to Result.ChildCount - 1 do
    begin
      if (AOffset >= Result[mIndex].StartOffset) and (AOffset < Result[mIndex].EndOffset) then
      begin
        Result := Result[mIndex];
        mFound := True;
        Break;
      end;
    end;
  until not mFound;
end;

/// <summary>Lohnt ein Alias für ANode?</summary>
function Worth(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.TypeReference:
      Result := ANode.FindChild(TSyntaxKind.GenericArgs) <> nil;
    TSyntaxKind.ArrayType, TSyntaxKind.SetType, TSyntaxKind.ProcedureType:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Gehört ANode zu einem Typausdruck: Typ, Typargumente oder Parameter eines prozeduralen Typs?</summary>
function InTypeChain(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.GenericArgs:
      Result := True;
    TSyntaxKind.Parameters:
      Result := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.ProcedureType);
    TSyntaxKind.Parameter:
      Result := (ANode.Parent <> nil) and InTypeChain(ANode.Parent);
  else
    Result := ANode.Kind in TTypeAliasNames.cTypeKinds;
  end;
end;

function ChildIndex(AParent, AChild: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to AParent.ChildCount - 1 do
  begin
    if AParent[mIndex] = AChild then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Darf ANode ein Alias werden? Nicht als ganze Typdeklaration (das ist schon einer) und nicht als offenes
/// Array eines Parameters (array of X wäre danach ein dynamisches Array).</summary>
function Allowed(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (mParent <> nil) and (mParent.Kind <> TSyntaxKind.TypeDecl) and
    not ((ANode.Kind = TSyntaxKind.ArrayType) and (mParent.Kind = TSyntaxKind.Parameter));
  if Result and not TTypeAliasNames.IsTypeNode(mParent) and (mParent.Kind <> TSyntaxKind.GenericArgs) then
  begin
    Result := mParent.Kind in TTypeAliasNames.cDeclarationContexts;
  end;
end;

/// <summary>Generische Parameter der umgebenden Typen und Routinen von ANode.</summary>
function GenericParamsAround(ANode: TSyntaxNode): TArray<string>;
var
  mCurrent, mParams: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mCurrent := ANode.Parent;
  while mCurrent <> nil do
  begin
    mParams := nil;
    if mCurrent.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.RoutineHeader] then
    begin
      mParams := mCurrent.FindChild(TSyntaxKind.GenericParams);
    end;
    if (mParams = nil) and (mCurrent.Kind = TSyntaxKind.RoutineDecl) and
      (mCurrent.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
    begin
      mParams := mCurrent.FindChild(TSyntaxKind.RoutineHeader).FindChild(TSyntaxKind.GenericParams);
    end;
    if mParams <> nil then
    begin
      for mIndex := 0 to mParams.ChildCount - 1 do
      begin
        Result := Result + [mParams[mIndex].Name];
      end;
    end;
    mCurrent := mCurrent.Parent;
  end;
end;

/// <summary>Die Namen aus AParams, die ANode als Typ nutzt, durch Komma getrennt.</summary>
function UsedParams(ANode: TSyntaxNode; const AParams: TArray<string>): string;
var
  mUsed: TArray<string>;
  mName: string;
begin
  Result := '';
  if AParams = nil then
  begin
    Exit;
  end;
  mUsed := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if (AChild.Kind = TSyntaxKind.TypeReference) and (Pos('.', AChild.Name) = 0) and
        (IndexText(AChild.Name, AParams) >= 0) and (IndexText(AChild.Name, mUsed) < 0) then
      begin
        mUsed := mUsed + [AChild.Name];
      end;
      Result := True;
    end);
  for mName in mUsed do
  begin
    if Result = '' then
    begin
      Result := mName;
    end
    else
    begin
      Result := Result + ', ' + mName;
    end;
  end;
end;

function IsIdentifier(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AName <> '') and CharInSet(AName[1], ['A'..'Z', 'a'..'z', '_']) and
    not TPascalLexer.IsReservedWord(AName);
  for mIndex := 2 to Length(AName) do
  begin
    if not CharInSet(AName[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Abschnitt (interface, implementation) bzw. Wurzel, in dem ANode steht.</summary>
function SectionOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and not (Result.Kind in [TSyntaxKind.InterfaceSection,
    TSyntaxKind.ImplementationSection]) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Deklaration direkt unter dem Abschnitt, die ANode enthält.</summary>
function TopLevelOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Parent <> nil) and
    not (Result.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) do
  begin
    Result := Result.Parent;
  end;
end;

function InInterface(ANode: TSyntaxNode): Boolean;
begin
  Result := SectionOf(ANode).Kind = TSyntaxKind.InterfaceSection;
end;

{ TTypeAliasLookup }

class function TTypeAliasLookup.FromTree: TTypeAliasLookup;
begin
  Result.Key :=
    function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode): string
    begin
      Result := '';
    end;
  Result.NameTaken :=
    function(ATree: TSyntaxTree; const AFileName, AName: string; AOffset: Integer): Boolean
    var
      Taken: Boolean;
    begin
      Taken := False;
      ATree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          if (ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl,
            TSyntaxKind.RoutineDecl, TSyntaxKind.Field, TSyntaxKind.PropertyDecl]) and
            SameText(TTypeAliasNames.LastPart(ANode.Name), AName) then
          begin
            Taken := True;
          end;
          Result := not Taken;
        end);
      Result := Taken;
    end;
  Result.UnitOf :=
    function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode; out AImplementation: Boolean): string
    begin
      AImplementation := False;
      Result := '';
    end;
end;

{ TTypeAliasSource }

class function TTypeAliasSource.Create(const AFileName, AText: string; ATree: TSyntaxTree): TTypeAliasSource;
begin
  Result := Create(AFileName, AText, ATree, nil);
end;

class function TTypeAliasSource.Create(const AFileName, AText: string; ATree: TSyntaxTree;
  const AOffsets: TArray<Integer>): TTypeAliasSource;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Tree := ATree;
  Result.Offsets := AOffsets;
end;

{ TTypeAlias }

class function TTypeAlias.ScopeName(AScope: TTypeAliasScope): string;
begin
  case AScope of
    TTypeAliasScope.Here:
      Result := 'here';
    TTypeAliasScope.Project:
      Result := 'project';
  else
    Result := 'unit';
  end;
end;

class function TTypeAlias.ScopeOf(const AName: string; out AScope: TTypeAliasScope): Boolean;
begin
  Result := True;
  if SameText(AName, 'here') then
  begin
    AScope := TTypeAliasScope.Here;
  end
  else if SameText(AName, 'unit') then
  begin
    AScope := TTypeAliasScope.InUnit;
  end
  else if SameText(AName, 'project') then
  begin
    AScope := TTypeAliasScope.Project;
  end
  else
  begin
    AScope := TTypeAliasScope.InUnit;
    Result := False;
  end;
end;

{ TTypeAliasRequest }

class function TTypeAliasRequest.Create(const APosition: TTextPosition; const AName: string;
  AScope: TTypeAliasScope; const ALookup: TTypeAliasLookup): TTypeAliasRequest;
begin
  Result.Position := APosition;
  Result.Name := AName;
  Result.Scope := AScope;
  Result.Lookup := ALookup;
end;

/// <summary>Schlüssel eines Typnamens mit seinen Typargumenten.</summary>
function ReferenceKey(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  const ALookup: TTypeAliasLookup): string;
var
  mArgs: TSyntaxNode;
  mIndex: Integer;
  mName: string;
  mParts: TArray<string>;
begin
  mName := '';
  if Assigned(ALookup.Key) then
  begin
    mName := ALookup.Key(ATree, AFileName, ANode);
  end;
  if mName = '' then
  begin
    mName := TTypeAliasNames.LastPart(ANode.Name);
  end;
  Result := LowerCase(mName);
  mArgs := ANode.FindChild(TSyntaxKind.GenericArgs);
  if mArgs <> nil then
  begin
    mParts := nil;
    for mIndex := 0 to mArgs.ChildCount - 1 do
    begin
      mParts := mParts + [TTypeAlias.KeyOf(ATree, AFileName, mArgs[mIndex], ALookup)];
    end;
    Result := Result + '<' + string.Join(',', mParts) + '>';
  end;
end;

/// <summary>Äußerste Typnamen unter ANode (ohne ANode selbst).</summary>
function InnerReferences(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  mInner: TArray<TSyntaxNode>;
begin
  mInner := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      Result := True;
      if (AChild <> ANode) and (AChild.Kind = TSyntaxKind.TypeReference) then
      begin
        mInner := mInner + [AChild];
        Result := False;
      end;
    end);
  Result := mInner;
end;

/// <summary>Letzter Knoten aus ANodes, der AOffset enthält; nil ohne.</summary>
function NodeCovering(const ANodes: TArray<TSyntaxNode>; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ANodes) do
  begin
    if (AOffset >= ANodes[mIndex].StartOffset) and (AOffset < ANodes[mIndex].EndOffset) then
    begin
      Result := ANodes[mIndex];
    end;
  end;
end;

/// <summary>Zählt AToken zum Schlüssel von ANode: in ANode, hinter ASkip und kein Kommentar?</summary>
function InKeyRange(const AToken: TPascalToken; ANode: TSyntaxNode; ASkip: Integer): Boolean;
begin
  Result := (AToken.Offset >= ANode.StartOffset) and (AToken.Offset < ANode.EndOffset) and
    (AToken.Offset >= ASkip) and (AToken.Kind <> TPascalTokenKind.Comment);
end;

/// <summary>Schlüssel übriger Ausdrücke: Text ohne Kommentare, Typnamen darin über ihren Schlüssel.</summary>
function ExpressionKey(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  const ALookup: TTypeAliasLookup): string;
var
  mInner: TArray<TSyntaxNode>;
  mParts: TArray<string>;
  mIndex, mSkip: Integer;
  mToken: TPascalToken;
  mChild: TSyntaxNode;
begin
  mInner := InnerReferences(ANode);
  mParts := nil;
  mSkip := -1;
  for mIndex := ATree.FirstTokenFrom(ANode.StartOffset) to High(ATree.Tokens) do
  begin
    mToken := ATree.Tokens[mIndex];
    if not InKeyRange(mToken, ANode, mSkip) then
    begin
      Continue;
    end;
    mChild := NodeCovering(mInner, mToken.Offset);
    if mChild <> nil then
    begin
      mParts := mParts + [TTypeAlias.KeyOf(ATree, AFileName, mChild, ALookup)];
      mSkip := mChild.EndOffset;
    end
    else
    begin
      mParts := mParts + [LowerCase(mToken.Text)];
    end;
  end;
  Result := string.Join(' ', mParts);
end;

class function TTypeAlias.KeyOf(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  const ALookup: TTypeAliasLookup): string;
begin
  if ANode.Kind = TSyntaxKind.TypeReference then
  begin
    Result := ReferenceKey(ATree, AFileName, ANode, ALookup);
  end
  else
  begin
    Result := ExpressionKey(ATree, AFileName, ANode, ALookup);
  end;
end;

/// <summary>Freier Name ab ABase: ABase, ABase2, ABase3 …</summary>
function FreeName(ATree: TSyntaxTree; const AFileName, ABase: string; AOffset: Integer;
  const ALookup: TTypeAliasLookup): string;
var
  mNumber: Integer;
begin
  Result := ABase;
  mNumber := 1;
  while Assigned(ALookup.NameTaken) and ALookup.NameTaken(ATree, AFileName, Result, AOffset) and (mNumber < 50) do
  begin
    Inc(mNumber);
    Result := ABase + IntToStr(mNumber);
  end;
end;

function MakeTarget(const AText: string; ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  const ALookup: TTypeAliasLookup): TTypeAliasTarget;
begin
  Result := Default(TTypeAliasTarget);
  Result.StartOffset := ANode.StartOffset;
  Result.EndOffset := ANode.EndOffset;
  Result.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  Result.TypeText := NodeText(AText, ANode);
  Result.Kind := ANode.Kind;
  Result.OpenParams := UsedParams(ANode, GenericParamsAround(ANode));
  Result.Suggestion := FreeName(ATree, AFileName, TTypeAliasNames.Suggest(ANode), ANode.StartOffset, ALookup);
end;

class function TTypeAlias.Targets(const AText: string; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; const ALookup: TTypeAliasLookup): TArray<TTypeAliasTarget>;
var
  mLines: TLineTable;
  mNode, mOuter, mInner: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mLines := TLineTable.Build(AText);
  mNode := NodeAt(ATree.Root, mLines.OffsetAt(APosition));
  mOuter := nil;
  mInner := nil;
  while (mNode <> nil) and InTypeChain(mNode) do
  begin
    if (mNode.Kind in TTypeAliasNames.cTypeKinds) and Worth(mNode) and Allowed(mNode) then
    begin
      if mInner = nil then
      begin
        mInner := mNode;
      end;
      mOuter := mNode;
    end;
    mNode := mNode.Parent;
  end;
  if mOuter = nil then
  begin
    Exit;
  end;
  Result := [MakeTarget(AText, ATree, AFileName, mOuter, ALookup)];
  if mInner <> mOuter then
  begin
    Result := Result + [MakeTarget(AText, ATree, AFileName, mInner, ALookup)];
  end;
end;

type
  /// <summary>Eine zu ersetzende Stelle.</summary>
  TAliasSite = record
    Node: TSyntaxNode;
    Start: Integer;
    Stop: Integer;
  end;

/// <summary>Alle Ausdrücke in ATree mit dem Schlüssel AKey, die ein Alias ersetzen darf; ineinander liegende nur
/// einmal (der äußere).</summary>
function SitesIn(ATree: TSyntaxTree; const AFileName, AKey: string; AKind: TSyntaxKind;
  const ALookup: TTypeAliasLookup): TArray<TAliasSite>;
var
  mSites: TArray<TAliasSite>;
begin
  mSites := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Site: TAliasSite;
    begin
      Result := True;
      if (ANode.Kind <> AKind) or not Allowed(ANode) or
        (UsedParams(ANode, GenericParamsAround(ANode)) <> '') or
        (TTypeAlias.KeyOf(ATree, AFileName, ANode, ALookup) <> AKey) then
      begin
        Exit;
      end;
      Site.Node := ANode;
      Site.Start := ANode.StartOffset;
      Site.Stop := ANode.EndOffset;
      mSites := mSites + [Site];
      Result := False;
    end);
  Result := mSites;
end;

/// <summary>Anfang der Zeile von AOffset, über unmittelbar darüber stehende Kommentarzeilen hinweg.</summary>
function LineAbove(const ALines: TLineTable; const AText: string; AOffset: Integer): Integer;
var
  mLine: Integer;
  mContent: string;
begin
  mLine := ALines.PositionAt(AOffset).Line;
  while mLine > 0 do
  begin
    mContent := Trim(Copy(AText, ALines.LineStart(mLine - 1) + 1, ALines.LineContentEnd(mLine - 1) -
      ALines.LineStart(mLine - 1)));
    if not (StartsStr('//', mContent) or StartsStr('{', mContent) and not StartsStr('{$', mContent) or
      StartsStr('(*', mContent)) then
    begin
      Break;
    end;
    Dec(mLine);
  end;
  Result := ALines.LineStart(mLine);
end;

/// <summary>In der Unit deklarierter Typ (oberste Ebene) namens AName, ohne Vorwärtsdeklarationen; nil ohne.
/// AForwardEnd: Ende der ersten Vorwärtsdeklaration, sonst -1.</summary>
function LocalType(ATree: TSyntaxTree; const AName: string; out AForwardEnd: Integer): TSyntaxNode;
var
  mFound: TSyntaxNode;
  mForwardEnd: Integer;
begin
  mFound := nil;
  mForwardEnd := -1;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
        TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection];
      if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) then
      begin
        if ANode.FindChild(TSyntaxKind.ForwardType) <> nil then
        begin
          if mForwardEnd < 0 then
          begin
            mForwardEnd := ANode.EndOffset;
          end;
        end
        else if mFound = nil then
        begin
          mFound := ANode;
        end;
      end;
    end);
  AForwardEnd := mForwardEnd;
  Result := mFound;
end;

/// <summary>Typnamen in ANode (auch in Typargumenten und Elementen).</summary>
function NamesIn(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  mNames: TArray<TSyntaxNode>;
begin
  mNames := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild.Kind = TSyntaxKind.TypeReference then
      begin
        mNames := mNames + [AChild];
      end;
      Result := True;
    end);
  Result := mNames;
end;

/// <summary>Bindet die Unit von ATree AUnitName so ein, dass die Stelle an AOffset sie sieht?</summary>
function SeesUnit(ATree: TSyntaxTree; const AUnitName: string; AOffset: Integer): Boolean;
var
  mReference: TUsesReference;
  mImplementation_: TSyntaxNode;
  mInImplementation, mBefore: Boolean;
begin
  Result := False;
  mImplementation_ := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  mInImplementation := (mImplementation_ <> nil) and (AOffset >= mImplementation_.StartOffset);
  for mReference in TUsesClauses.References(ATree.Tokens) do
  begin
    if (mReference.List <> TUsesListKind.UsesList) or not (SameText(mReference.Name, AUnitName) or
      EndsText('.' + AUnitName, mReference.Name)) then
    begin
      Continue;
    end;
    mBefore := (mImplementation_ = nil) or (mReference.Range.StartPos.Line < mImplementation_.StartPos.Line) or
      (mReference.Range.StartPos.Line = mImplementation_.StartPos.Line) and
      (mReference.Range.StartPos.Character < mImplementation_.StartPos.Character);
    if mInImplementation or mBefore then
    begin
      Exit(True);
    end;
  end;
end;

type
  TFileChange = record
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    Edits: TArray<TTextEdit>;
  end;

/// <summary>Prüft, dass jede Datei nach den Änderungen so fehlerfrei parst wie vorher, und baut das Ergebnis.
/// </summary>
function Finish(const AChanges: TArray<TFileChange>; var AResult: TTypeAliasResult; out AReason: string): Boolean;
var
  mChange: TFileChange;
  mItem: TTypeAliasFileEdits;
  mTree: TSyntaxTree;
begin
  for mChange in AChanges do
  begin
    if mChange.Edits = nil then
    begin
      Continue;
    end;
    mTree := TSyntaxTreeCache.Parse(TChangeSignature.ApplyEdits(mChange.Text, mChange.Edits));
    try
      if Length(mTree.Diagnostics) > Length(mChange.Tree.Diagnostics) then
      begin
        Exit(Fail(cTexts[TEditingTypeAliasText.AfterTheChangeNoLonger].Fmt([ExtractFileName(mChange.FileName),
          mTree.Diagnostics[0].StartPos.Line + 1, mTree.Diagnostics[0].Message]),
          AReason));
      end;
    finally
      mTree.Free;
    end;
    mItem.FileName := mChange.FileName;
    mItem.Edits := mChange.Edits;
    AResult.Files := AResult.Files + [mItem];
  end;
  Result := True;
end;

function Edit(const ALines: TLineTable; AStart, AStop: Integer; const AText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALines.PositionAt(AStart), ALines.PositionAt(AStop)), AText);
end;

/// <summary>Änderung an der Datei ASource, noch ohne Edits.</summary>
function FileChange(const ASource: TTypeAliasSource): TFileChange;
begin
  Result := Default(TFileChange);
  Result.FileName := ASource.FileName;
  Result.Text := ASource.Text;
  Result.Tree := ASource.Tree;
end;

/// <summary>Knoten in ATree, der genau den Ausdruck ATarget umfasst; nil ohne.</summary>
function TargetNode(ATree: TSyntaxTree; const ATarget: TTypeAliasTarget): TSyntaxNode;
begin
  Result := NodeAt(ATree.Root, ATarget.StartOffset);
  while (Result <> nil) and not ((Result.Kind = ATarget.Kind) and (Result.StartOffset = ATarget.StartOffset) and
    (Result.EndOffset = ATarget.EndOffset)) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Stehen alle in der Unit deklarierten Typen, die ANode nennt, im interface-Teil?</summary>
function NamesInInterface(ATree: TSyntaxTree; ANode: TSyntaxNode): Boolean;
var
  mNameNode, mLocal: TSyntaxNode;
  mForwardEnd: Integer;
begin
  Result := True;
  for mNameNode in NamesIn(ANode) do
  begin
    mLocal := LocalType(ATree, TTypeAliasNames.LastPart(mNameNode.Name), mForwardEnd);
    if (mLocal <> nil) and not InInterface(mLocal) then
    begin
      Result := False;
    end;
  end;
end;


type
  /// <summary>Arbeitsstand von TTypeAlias.Introduce: Ausdruck Node mit Schlüssel Key, seine Stellen Sites (First die
  /// erste), Einfügestelle Insert mit Declaration, die Änderungen und das Ergebnis Outcome.</summary>
  TIntroduction = record
    Declaring: TTypeAliasSource;
    Others: TArray<TTypeAliasSource>;
    Name: string;
    Scope: TTypeAliasScope;
    Lookup: TTypeAliasLookup;
    Lines: TLineTable;
    LineBreak: string;
    Target: TTypeAliasTarget;
    Node: TSyntaxNode;
    Key: string;
    Sites: TArray<TAliasSite>;
    First: TSyntaxNode;
    ExportNeeded: Boolean;
    Top: TSyntaxNode;
    Insert: Integer;
    Indent: string;
    Declaration: string;
    Changes: TArray<TFileChange>;
    PreviewLines: TArray<string>;
    Outcome: TTypeAliasResult;
    class function Create(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
      const ARequest: TTypeAliasRequest): TIntroduction; static;
    function TargetIssue(const APosition: TTextPosition): string;
    procedure CollectSites;
    procedure DecideExport;
    function AliasLine: string;
    procedure AppendTo(ASection: TSyntaxNode);
    function PlaceInInterface: string;
    procedure PlaceInTypeSection;
    procedure PlaceBefore(ASection: TSyntaxNode);
    function PlacementIssue: string;
    function ForwardKindOf(ALocal: TSyntaxNode): string;
    function ForwardsIssue(out AForwards: string): string;
    procedure AddOwnChange(const AForwards: string);
    function SiteBlocked(const AOther: TTypeAliasSource; const AUnitName: string; AStart: Integer): Boolean;
    procedure AddOtherChange(const AOther: TTypeAliasSource; const AUnitName: string);
    procedure AddOtherChanges;
    function PreviewText(const AResult: TTypeAliasResult): string;
  end;

class function TIntroduction.Create(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
  const ARequest: TTypeAliasRequest): TIntroduction;
begin
  Result := Default(TIntroduction);
  Result.Declaring := ADeclaring;
  Result.Others := AOthers;
  Result.Name := ARequest.Name;
  Result.Scope := ARequest.Scope;
  Result.Lookup := ARequest.Lookup;
  Result.Lines := TLineTable.Build(ADeclaring.Text);
  Result.LineBreak := TTextLines.LineBreakOf(ADeclaring.Text);
  Result.Indent := '  ';
end;

/// <summary>Sucht den Ausdruck an APosition (innerer, wenn er dort beginnt) und seinen Schlüssel; Grund, wenn es
/// keinen gibt oder der Name ungültig ist, sonst ''.</summary>
function TIntroduction.TargetIssue(const APosition: TTextPosition): string;
var
  mCandidates: TArray<TTypeAliasTarget>;
  mIndex: Integer;
begin
  if not IsIdentifier(Name) then
  begin
    Exit(cTexts[TEditingTypeAliasText.IsNotAValidIdentifier].Fmt([Name]));
  end;
  mCandidates := TTypeAlias.Targets(Declaring.Text, Declaring.Tree, Declaring.FileName, APosition, Lookup);
  if mCandidates = nil then
  begin
    Exit(cTexts[TEditingTypeAliasText.ThereIsNoTypeExpression].Text);
  end;
  Target := mCandidates[0];
  for mIndex := 1 to High(mCandidates) do
  begin
    if mCandidates[mIndex].StartOffset = Lines.OffsetAt(APosition) then
    begin
      Target := mCandidates[mIndex];
    end;
  end;
  Result := '';
  Node := TargetNode(Declaring.Tree, Target);
  if Target.OpenParams <> '' then
  begin
    Result := Format(TTypeAlias.OpenParamsReason, [Target.OpenParams]);
  end
  else if Node = nil then
  begin
    Result := cTexts[TEditingTypeAliasText.ThereIsNoTypeExpression].Text;
  end
  else
  begin
    Key := TTypeAlias.KeyOf(Declaring.Tree, Declaring.FileName, Node, Lookup);
  end;
end;

/// <summary>Stellen der Unit: nur der Ausdruck selbst oder alle gleichen; First ist die erste.</summary>
procedure TIntroduction.CollectSites;
var
  mSite: TAliasSite;
begin
  if Scope = TTypeAliasScope.Here then
  begin
    mSite.Node := Node;
    mSite.Start := Node.StartOffset;
    mSite.Stop := Node.EndOffset;
    Sites := [mSite];
  end
  else
  begin
    Sites := SitesIn(Declaring.Tree, Declaring.FileName, Key, Node.Kind, Lookup);
  end;
  First := Node;
  for mSite in Sites do
  begin
    if mSite.Start < First.StartOffset then
    begin
      First := mSite.Node;
    end;
  end;
end;

/// <summary>Im Projekt steht der Alias im interface-Teil, sonst sehen ihn andere Units nicht; mit Typen aus dem
/// implementation-Teil geht das nicht, dann nur in der Unit.</summary>
procedure TIntroduction.DecideExport;
begin
  ExportNeeded := (Scope = TTypeAliasScope.Project) and (Others <> nil) and not InInterface(First);
  if ExportNeeded and not NamesInInterface(Declaring.Tree, Node) then
  begin
    ExportNeeded := False;
    Scope := TTypeAliasScope.InUnit;
    Outcome.Warnings := Outcome.Warnings + [cTexts[TEditingTypeAliasText.UsesTypesFromTheImplementation].Fmt([
      Target.TypeText])];
  end;
end;

function TIntroduction.AliasLine: string;
begin
  Result := Indent + Name + ' = ' + Target.TypeText + ';' + LineBreak;
end;

/// <summary>Einfügen hinter der letzten Deklaration des type-Abschnitts ASection, eingerückt wie sie.</summary>
procedure TIntroduction.AppendTo(ASection: TSyntaxNode);
var
  mLast: TSyntaxNode;
begin
  mLast := ASection[ASection.ChildCount - 1];
  Insert := Lines.LineStart(Lines.PositionAt(mLast.EndOffset).Line + 1);
  Indent := TTextLines.IndentOf(Declaring.Text, Lines.PositionAt(mLast.StartOffset).Line);
  Declaration := AliasLine;
end;

/// <summary>Ans Ende des interface-Teils: in den letzten type-Abschnitt oder als neuer Abschnitt.</summary>
function TIntroduction.PlaceInInterface: string;
var
  mSection: TSyntaxNode;
begin
  mSection := Declaring.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if mSection = nil then
  begin
    Exit(cTexts[TEditingTypeAliasText.TheUnitHasNoInterface].Text);
  end;
  Result := '';
  Top := nil;
  if mSection.ChildCount > 0 then
  begin
    Top := mSection[mSection.ChildCount - 1];
  end;
  if (Top <> nil) and (Top.Kind = TSyntaxKind.TypeSection) and (Top.ChildCount > 0) then
  begin
    AppendTo(Top);
    Exit;
  end;
  Insert := Lines.LineStart(Lines.PositionAt(mSection.EndOffset).Line);
  if Top <> nil then
  begin
    Insert := Lines.LineStart(Lines.PositionAt(Top.EndOffset).Line + 1);
  end;
  Declaration := LineBreak + 'type' + LineBreak + AliasLine;
end;

/// <summary>Vor die Typdeklaration des Abschnitts Top, in der die erste Verwendung steht.</summary>
procedure TIntroduction.PlaceInTypeSection;
var
  mIndex: Integer;
begin
  for mIndex := 0 to Top.ChildCount - 1 do
  begin
    if (First.StartOffset >= Top[mIndex].StartOffset) and (First.StartOffset < Top[mIndex].EndOffset) then
    begin
      Top := Top[mIndex];
      Break;
    end;
  end;
  Insert := LineAbove(Lines, Declaring.Text, Top.StartOffset);
  Indent := TTextLines.IndentOf(Declaring.Text, Lines.PositionAt(Top.StartOffset).Line);
  Declaration := AliasLine;
end;

/// <summary>Vor die Deklaration Top in ASection: ans Ende eines type-Abschnitts direkt davor, sonst als neuer.
/// </summary>
procedure TIntroduction.PlaceBefore(ASection: TSyntaxNode);
var
  mPrevious: TSyntaxNode;
  mIndex: Integer;
begin
  mPrevious := nil;
  mIndex := ChildIndex(ASection, Top);
  if mIndex > 0 then
  begin
    mPrevious := ASection[mIndex - 1];
  end;
  if (mPrevious <> nil) and (mPrevious.Kind = TSyntaxKind.TypeSection) and (mPrevious.ChildCount > 0) then
  begin
    AppendTo(mPrevious);
  end
  else
  begin
    Insert := LineAbove(Lines, Declaring.Text, Top.StartOffset);
    Declaration := 'type' + LineBreak + AliasLine + LineBreak;
  end;
end;

/// <summary>Einfügestelle: vor der Typdeklaration mit der ersten Verwendung, sonst ein neuer type-Abschnitt; im
/// Projekt am Ende des interface-Teils. Grund, wenn der Name vergeben ist oder der interface-Teil fehlt.</summary>
function TIntroduction.PlacementIssue: string;
begin
  if Assigned(Lookup.NameTaken) and Lookup.NameTaken(Declaring.Tree, Declaring.FileName, Name, First.StartOffset) then
  begin
    Exit(cTexts[TEditingTypeAliasText.TheNameIsAlreadyTaken].Fmt([Name]));
  end;
  Result := '';
  if ExportNeeded then
  begin
    Result := PlaceInInterface;
    Exit;
  end;
  Top := TopLevelOf(First);
  if Top.Kind = TSyntaxKind.TypeSection then
  begin
    PlaceInTypeSection;
  end
  else
  begin
    PlaceBefore(SectionOf(First));
  end;
end;

/// <summary>Art der Vorwärtsdeklaration für den Typ ALocal der Unit, der die erste Verwendung enthält: class bzw.
/// interface; '' wenn keine geht.</summary>
function TIntroduction.ForwardKindOf(ALocal: TSyntaxNode): string;
begin
  Result := '';
  if not ((ALocal.StartOffset <= First.StartOffset) and (First.StartOffset < ALocal.EndOffset) and (Top <> nil) and
    (ALocal = Top)) then
  begin
    Exit;
  end;
  if ALocal.FindChild(TSyntaxKind.ClassType) <> nil then
  begin
    Result := 'class';
  end
  else if ALocal.FindChild(TSyntaxKind.InterfaceType) <> nil then
  begin
    Result := 'interface';
  end;
end;

/// <summary>Typen der Unit, die der Ausdruck nennt, müssen vor dem Alias stehen; die eigene Klasse geht per
/// Vorwärtsdeklaration (AForwards). Grund, wenn ein Typ erst danach deklariert ist.</summary>
function TIntroduction.ForwardsIssue(out AForwards: string): string;
var
  mNameNode, mLocal: TSyntaxNode;
  mForwardEnd: Integer;
  mKind: string;
begin
  AForwards := '';
  Result := '';
  for mNameNode in NamesIn(Node) do
  begin
    mLocal := LocalType(Declaring.Tree, TTypeAliasNames.LastPart(mNameNode.Name), mForwardEnd);
    if (mLocal = nil) or (mLocal.EndOffset <= Insert) or (mForwardEnd >= 0) and (mForwardEnd <= Insert) then
    begin
      Continue;
    end;
    mKind := ForwardKindOf(mLocal);
    if mKind = '' then
    begin
      Exit(cTexts[TEditingTypeAliasText.IsNotDeclaredYetBefore].Fmt([mLocal.Name, Target.TypeText]));
    end;
    if not ContainsText(AForwards, ' ' + mLocal.Name + ' = ') then
    begin
      AForwards := AForwards + Indent + mLocal.Name + ' = ' + mKind + ';' + LineBreak;
    end;
    Outcome.Warnings := Outcome.Warnings + [cTexts[TEditingTypeAliasText.GetsAForwardDeclarationBefore].Fmt([
      mLocal.Name])];
  end;
end;

/// <summary>Deklaration (mit AForwards davor) und die Stellen der eigenen Unit.</summary>
procedure TIntroduction.AddOwnChange(const AForwards: string);
var
  mChange: TFileChange;
  mSite: TAliasSite;
begin
  mChange := FileChange(Declaring);
  if AForwards <> '' then
  begin
    Declaration := AForwards + Declaration;
  end;
  mChange.Edits := [Edit(Lines, Insert, Insert, Declaration)];
  PreviewLines := nil;
  for mSite in Sites do
  begin
    mChange.Edits := mChange.Edits + [Edit(Lines, mSite.Start, mSite.Stop, Name)];
    PreviewLines := PreviewLines + [Where(Declaring.FileName, Lines.PositionAt(mSite.Start).Line)];
  end;
  Outcome.Places := Length(Sites);
  Changes := [mChange];
end;

/// <summary>Bleibt die Stelle AStart in AOther, weil AOther die Unit AUnitName nicht einbindet oder den Namen selbst
/// vergibt?</summary>
function TIntroduction.SiteBlocked(const AOther: TTypeAliasSource; const AUnitName: string; AStart: Integer): Boolean;
begin
  Result := not SeesUnit(AOther.Tree, AUnitName, AStart) or Assigned(Lookup.NameTaken) and
    Lookup.NameTaken(AOther.Tree, AOther.FileName, Name, AStart);
end;

/// <summary>Gleiche Ausdrücke in der Unit AOther, die AUnitName einbindet.</summary>
procedure TIntroduction.AddOtherChange(const AOther: TTypeAliasSource; const AUnitName: string);
var
  mSites: TArray<TAliasSite>;
  mSite: TAliasSite;
  mChange: TFileChange;
  mLines: TLineTable;
  mSkipped: Integer;
begin
  mSites := SitesIn(AOther.Tree, AOther.FileName, Key, Node.Kind, Lookup);
  if mSites = nil then
  begin
    Exit;
  end;
  mChange := FileChange(AOther);
  mLines := TLineTable.Build(AOther.Text);
  mSkipped := 0;
  for mSite in mSites do
  begin
    if SiteBlocked(AOther, AUnitName, mSite.Start) then
    begin
      Inc(mSkipped);
      Continue;
    end;
    mChange.Edits := mChange.Edits + [Edit(mLines, mSite.Start, mSite.Stop, Name)];
    PreviewLines := PreviewLines + [Where(AOther.FileName, mLines.PositionAt(mSite.Start).Line)];
    Inc(Outcome.Places);
  end;
  if mSkipped > 0 then
  begin
    Outcome.Warnings := Outcome.Warnings + [cTexts[TEditingTypeAliasText.EqualExpressionsRemainNotUsed].Fmt([
      ExtractFileName(AOther.FileName), mSkipped, AUnitName, Name])];
  end;
  if mChange.Edits <> nil then
  begin
    Changes := Changes + [mChange];
  end;
end;

/// <summary>Andere Units des Projekts: nur, wenn sie die Unit einbinden und den Namen nicht selbst vergeben.
/// </summary>
procedure TIntroduction.AddOtherChanges;
var
  mOther: TTypeAliasSource;
  mUnitName: string;
begin
  if (Scope = TTypeAliasScope.Project) and (InInterface(First) or ExportNeeded) then
  begin
    mUnitName := TUsesClauses.OwnName(Declaring.Tree.Tokens);
    for mOther in Others do
    begin
      if not SameText(mOther.FileName, Declaring.FileName) and (mOther.Tree <> nil) then
      begin
        AddOtherChange(mOther, mUnitName);
      end;
    end;
  end
  else if (Scope = TTypeAliasScope.Project) and (Others <> nil) then
  begin
    Outcome.Warnings := Outcome.Warnings + [cTexts[TEditingTypeAliasText.IsInTheImplementationPart].Fmt([Name])];
  end;
end;

function TIntroduction.PreviewText(const AResult: TTypeAliasResult): string;
var
  mVisible: string;
begin
  mVisible := cTexts[TEditingTypeAliasText.ImplementationPart].Text;
  if InInterface(First) or ExportNeeded then
  begin
    mVisible := cTexts[TEditingTypeAliasText.InterfacePart].Text;
  end;
  Result := cTexts[TEditingTypeAliasText.InPlacesInFiles].Fmt([Name, Target.TypeText, mVisible, AResult.Places,
    Length(AResult.Files)]) + sLineBreak + TTypeAlias.CompatibilityNote;
  if PreviewLines <> nil then
  begin
    Result := Result + sLineBreak + string.Join(sLineBreak, PreviewLines);
  end;
end;

class function TTypeAlias.Introduce(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
  const ARequest: TTypeAliasRequest; out AResult: TTypeAliasResult; out AReason: string): Boolean;
var
  mIntroduction: TIntroduction;
  mForwards: string;
begin
  Result := False;
  mIntroduction := TIntroduction.Create(ADeclaring, AOthers, ARequest);
  AReason := mIntroduction.TargetIssue(ARequest.Position);
  if AReason = '' then
  begin
    mIntroduction.CollectSites;
    mIntroduction.DecideExport;
    AReason := mIntroduction.PlacementIssue;
  end;
  if AReason = '' then
  begin
    AReason := mIntroduction.ForwardsIssue(mForwards);
  end;
  AResult := mIntroduction.Outcome;
  if AReason <> '' then
  begin
    Exit;
  end;
  mIntroduction.AddOwnChange(mForwards);
  mIntroduction.AddOtherChanges;
  AResult := mIntroduction.Outcome;
  if Finish(mIntroduction.Changes, AResult, AReason) then
  begin
    AResult.Preview := mIntroduction.PreviewText(AResult);
    Result := True;
  end;
end;

/// <summary>Typdeklaration um AOffset; nil ohne.</summary>
function AliasDecl(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
begin
  Result := NodeAt(ATree.Root, AOffset);
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.TypeDecl) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Letzter Typausdruck unter der Typdeklaration ADecl; nil ohne.</summary>
function AliasExpression(ADecl: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[mIndex].Kind in TTypeAliasNames.cTypeKinds then
    begin
      Result := ADecl[mIndex];
    end;
  end;
end;

/// <summary>X = type Y: steht "type" zwischen Name und Ausdruck?</summary>
function IsDistinctType(ATree: TSyntaxTree; ADecl, AExpression: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := ATree.FirstTokenFrom(ADecl.StartOffset + 1) to High(ATree.Tokens) do
  begin
    if (ATree.Tokens[mIndex].Offset > ADecl.StartOffset) and (ATree.Tokens[mIndex].Offset < AExpression.StartOffset)
      and ATree.Tokens[mIndex].IsKeyword('type') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Grund, warum ADecl an AOffset kein auflösbarer Alias X = Y ist; '' wenn er es ist.</summary>
function AliasIssue(ATree: TSyntaxTree; ADecl: TSyntaxNode; AOffset: Integer): string;
var
  mExpression: TSyntaxNode;
begin
  if (ADecl = nil) or (AOffset >= ADecl.StartOffset + Length(ADecl.Name)) then
  begin
    Exit(cTexts[TEditingTypeAliasText.ThereIsNoTypeAlias].Text);
  end;
  if ADecl.FindChild(TSyntaxKind.GenericParams) <> nil then
  begin
    Exit(cTexts[TEditingTypeAliasText.IsGeneric].Fmt([ADecl.Name]));
  end;
  mExpression := AliasExpression(ADecl);
  Result := '';
  if (mExpression = nil) or (ADecl.ChildCount <> 1) then
  begin
    Result := cTexts[TEditingTypeAliasText.IsNotAnAlias].Fmt([ADecl.Name]);
  end
  // X = type Y: eigener Typ.
  else if IsDistinctType(ATree, ADecl, mExpression) then
  begin
    Result := cTexts[TEditingTypeAliasText.TypeIsADistinctType].Fmt([ADecl.Name]);
  end;
end;

class function TTypeAlias.InlineTarget(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  out ATarget: TInlineAliasTarget; out AReason: string): Boolean;
var
  mDecl, mExpression: TSyntaxNode;
  mOffset: Integer;
begin
  ATarget := Default(TInlineAliasTarget);
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(Fail(cTexts[TEditingTypeAliasText.NoTree].Text, AReason));
  end;
  mOffset := TLineTable.Build(AText).OffsetAt(APosition);
  mDecl := AliasDecl(ATree, mOffset);
  AReason := AliasIssue(ATree, mDecl, mOffset);
  Result := AReason = '';
  if Result then
  begin
    mExpression := AliasExpression(mDecl);
    ATarget.Name := mDecl.Name;
    ATarget.TypeText := NodeText(AText, mExpression);
    ATarget.Kind := mExpression.Kind;
    ATarget.NamePosition := mDecl.StartPos;
  end;
end;

/// <summary>Der Knoten, den eine Verwendung an AOffset ersetzt: TypeReference, Bezeichner oder qualifizierter
/// Zugriff Unit.X; ATypePosition: an der Stelle steht ein Typ (kein Ausdruck).</summary>
function UseNode(ATree: TSyntaxTree; AOffset: Integer; out ATypePosition: Boolean): TSyntaxNode;
begin
  Result := NodeAt(ATree.Root, AOffset);
  ATypePosition := False;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.Identifier,
    TSyntaxKind.MemberAccess]) do
  begin
    Result := Result.Parent;
  end;
  if Result = nil then
  begin
    Exit;
  end;
  ATypePosition := Result.Kind = TSyntaxKind.TypeReference;
  // Unit.X als Ausdruck liefert NodeAt als MemberAccess selbst, X.Create dagegen den Bezeichner X darin.
end;

type
  /// <summary>Arbeitsstand von TTypeAlias.InlineAlias: Deklaration Decl des Alias Target, Units seiner Typen, ob
  /// andere Units sie sehen (Hidden), behaltene Verwendungen Kept, Änderungen und Ergebnis Outcome.</summary>
  TInlining = record
    Declaring: TTypeAliasSource;
    Lookup: TTypeAliasLookup;
    Target: TInlineAliasTarget;
    Lines: TLineTable;
    Decl: TSyntaxNode;
    Named: Boolean;
    Hidden: Boolean;
    Units: TArray<string>;
    Kept: Integer;
    Changes: TArray<TFileChange>;
    PreviewLines: TArray<string>;
    Outcome: TTypeAliasResult;
    class function Create(const ADeclaring: TTypeAliasSource; const ALookup: TTypeAliasLookup;
      const ATarget: TInlineAliasTarget): TInlining; static;
    procedure CollectUnits;
    function IsDeclarationName(AOffset: Integer): Boolean;
    function Replaceable(AUse: TSyntaxNode; ATypePosition: Boolean): Boolean;
    function ReplaceUses(const ASource: TTypeAliasSource; AOwn: Boolean; var AChange: TFileChange): Integer;
    function UsesIssue(const ASource: TTypeAliasSource; AFirstSite: Integer; var AChange: TFileChange): string;
    function SourceIssue(const ASource: TTypeAliasSource): string;
    function OwnChangeIndex: Integer;
    procedure RemoveAlias;
    function ChangesIssue(const AOthers: TArray<TTypeAliasSource>): string;
    function PreviewText(const AResult: TTypeAliasResult): string;
  end;

class function TInlining.Create(const ADeclaring: TTypeAliasSource; const ALookup: TTypeAliasLookup;
  const ATarget: TInlineAliasTarget): TInlining;
begin
  Result := Default(TInlining);
  Result.Declaring := ADeclaring;
  Result.Lookup := ALookup;
  Result.Target := ATarget;
  Result.Lines := TLineTable.Build(ADeclaring.Text);
  Result.Decl := AliasDecl(ADeclaring.Tree, Result.Lines.OffsetAt(ATarget.NamePosition));
  Result.Named := Result.Decl[0].Kind = TSyntaxKind.TypeReference;
  Result.CollectUnits;
end;

/// <summary>Units der Typen im Ausdruck, für andere Units; Typen aus dem implementation-Teil sehen sie nicht.
/// </summary>
procedure TInlining.CollectUnits;
var
  mNameNode: TSyntaxNode;
  mUnitName: string;
  mImplementation: Boolean;
begin
  Units := nil;
  Hidden := not InInterface(Decl);
  for mNameNode in NamesIn(Decl[0]) do
  begin
    mUnitName := '';
    mImplementation := False;
    if Assigned(Lookup.UnitOf) then
    begin
      mUnitName := Lookup.UnitOf(Declaring.Tree, Declaring.FileName, mNameNode, mImplementation);
    end;
    Hidden := Hidden or mImplementation;
    if (mUnitName <> '') and (IndexText(mUnitName, Units) < 0) then
    begin
      Units := Units + [mUnitName];
    end;
  end;
end;

/// <summary>Steht AOffset im Namen der Alias-Deklaration selbst?</summary>
function TInlining.IsDeclarationName(AOffset: Integer): Boolean;
begin
  Result := (AOffset >= Decl.StartOffset) and (AOffset < Decl.StartOffset + Length(Decl.Name));
end;

/// <summary>Lässt sich die Verwendung AUse ersetzen? Ohne Typnamen nimmt Delphi den Ausdruck nur in Deklarationen von
/// Feldern, Variablen, Konstanten und Typen an, nicht in Parametern, Ergebnissen, Properties, Typargumenten und
/// Ausdrücken.</summary>
function TInlining.Replaceable(AUse: TSyntaxNode; ATypePosition: Boolean): Boolean;
begin
  Result := (AUse <> nil) and (Named or ATypePosition and (AUse.Parent <> nil) and
    (AUse.Parent.Kind in cAnonymousContexts));
end;

/// <summary>Ersetzt die Verwendungen in ASource (AOwn: die Datei des Alias) durch den Ausdruck; Anfang der ersten
/// Stelle (im interface-Teil bevorzugt), -1 ohne.</summary>
function TInlining.ReplaceUses(const ASource: TTypeAliasSource; AOwn: Boolean; var AChange: TFileChange): Integer;
var
  mLines: TLineTable;
  mOffset, mStart, mStop: Integer;
  mUse: TSyntaxNode;
  mTypePosition: Boolean;
begin
  Result := -1;
  mLines := TLineTable.Build(ASource.Text);
  for mOffset in ASource.Offsets do
  begin
    if AOwn and IsDeclarationName(mOffset) then
    begin
      Continue;
    end;
    mUse := UseNode(ASource.Tree, mOffset, mTypePosition);
    if not Replaceable(mUse, mTypePosition) then
    begin
      Inc(Kept);
      Continue;
    end;
    mStart := mUse.StartOffset;
    mStop := mUse.EndOffset;
    if mUse.Kind = TSyntaxKind.TypeReference then
    begin
      mStop := mUse.StartOffset + Length(mUse.Name);
    end;
    AChange.Edits := AChange.Edits + [Edit(mLines, mStart, mStop, Target.TypeText)];
    PreviewLines := PreviewLines + [Where(ASource.FileName, mLines.PositionAt(mStart).Line)];
    Inc(Outcome.Places);
    if (Result < 0) or InInterface(mUse) and not InInterface(NodeAt(ASource.Tree.Root, Result)) then
    begin
      Result := mStart;
    end;
  end;
end;

/// <summary>Fehlende uses für die Typen des Ausdrucks in ASource, vor AFirstSite; Grund, wenn eine sich nicht
/// ergänzen lässt.</summary>
function TInlining.UsesIssue(const ASource: TTypeAliasSource; AFirstSite: Integer; var AChange: TFileChange): string;
var
  mUnitName, mLineBreak: string;
  mUsesEdit: TTextEdit;
begin
  Result := '';
  mLineBreak := TTextLines.LineBreakOf(ASource.Text);
  for mUnitName in Units do
  begin
    if SameText(mUnitName, TUsesClauses.OwnName(ASource.Tree.Tokens)) or
      TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ASource.Tree.Tokens), mUnitName, nil) then
    begin
      Continue;
    end;
    if not TUsesClauses.AddUnit(ASource.Tree.Tokens, AFirstSite, mUnitName, mLineBreak, mUsesEdit) then
    begin
      Exit(cTexts[TEditingTypeAliasText.UsesForCannotBeAdded].Fmt([ExtractFileName(ASource.FileName), mUnitName]));
    end;
    AChange.Edits := AChange.Edits + [mUsesEdit];
  end;
end;

/// <summary>Änderungen an ASource; andere Units behalten alle Verwendungen, wenn sie die Typen nicht sehen.</summary>
function TInlining.SourceIssue(const ASource: TTypeAliasSource): string;
var
  mOwn: Boolean;
  mChange: TFileChange;
  mFirstSite: Integer;
begin
  Result := '';
  mOwn := SameText(ASource.FileName, Declaring.FileName);
  if (ASource.Tree = nil) or (ASource.Offsets = nil) then
  begin
    Exit;
  end;
  if not mOwn and Hidden then
  begin
    Inc(Kept, Length(ASource.Offsets));
    Exit;
  end;
  mChange := FileChange(ASource);
  mFirstSite := ReplaceUses(ASource, mOwn, mChange);
  if not mOwn and (mFirstSite >= 0) then
  begin
    Result := UsesIssue(ASource, mFirstSite, mChange);
  end;
  if (Result = '') and (mChange.Edits <> nil) then
  begin
    Changes := Changes + [mChange];
  end;
end;

/// <summary>Index der Änderung an der Datei des Alias; legt sie an, wenn es sie noch nicht gibt.</summary>
function TInlining.OwnChangeIndex: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Changes) do
  begin
    if SameText(Changes[mIndex].FileName, Declaring.FileName) then
    begin
      Result := mIndex;
    end;
  end;
  if Result < 0 then
  begin
    Changes := Changes + [FileChange(Declaring)];
    Result := High(Changes);
  end;
end;

/// <summary>Entfernt den Alias, mit seinem type-Abschnitt, wenn er der einzige war.</summary>
procedure TInlining.RemoveAlias;
var
  mSection: TSyntaxNode;
  mStart, mStop, mIndex: Integer;
begin
  mSection := Decl.Parent;
  if (mSection <> nil) and (mSection.Kind = TSyntaxKind.TypeSection) and (mSection.ChildCount = 1) then
  begin
    mStart := Lines.LineStart(mSection.StartPos.Line);
    mStop := Lines.LineStart(mSection.EndPos.Line + 1);
  end
  else
  begin
    mStart := Lines.LineStart(Decl.StartPos.Line);
    mStop := Lines.LineStart(Decl.EndPos.Line + 1);
  end;
  if Decl.EndPos.Line + 1 >= Lines.LineCount then
  begin
    mStop := Length(Declaring.Text);
  end;
  mIndex := OwnChangeIndex;
  Changes[mIndex].Edits := Changes[mIndex].Edits + [Edit(Lines, mStart, mStop, '')];
end;

/// <summary>Ersetzt in ADeclaring und AOthers; ohne verbliebene Verwendung fällt der Alias weg. Grund, wenn uses
/// fehlen oder keine Verwendung ersetzbar ist.</summary>
function TInlining.ChangesIssue(const AOthers: TArray<TTypeAliasSource>): string;
var
  mSources: TArray<TTypeAliasSource>;
  mSource: TTypeAliasSource;
begin
  mSources := TArray<TTypeAliasSource>.Create(Declaring) + AOthers;
  for mSource in mSources do
  begin
    Result := SourceIssue(mSource);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  if Kept = 0 then
  begin
    RemoveAlias;
  end
  else
  begin
    Outcome.Warnings := Outcome.Warnings + [cTexts[TEditingTypeAliasText.UsesKeepParameterResultProperty].Fmt([Kept,
      Target.Name])];
  end;
  Result := '';
  if (Outcome.Places = 0) and (Kept > 0) then
  begin
    Result := cTexts[TEditingTypeAliasText.NoUseOfCanBe].Fmt([Target.Name]);
  end
  else if Outcome.Places = 0 then
  begin
    Outcome.Warnings := Outcome.Warnings + [cTexts[TEditingTypeAliasText.IsNotUsedAnywhere].Fmt([Target.Name])];
  end;
end;

function TInlining.PreviewText(const AResult: TTypeAliasResult): string;
begin
  Result := cTexts[TEditingTypeAliasText.IsReplacedByPlacesIn].Fmt([Target.Name, Target.TypeText,
    AResult.Places, Length(AResult.Files)]);
  if Kept = 0 then
  begin
    Result := Result + cTexts[TEditingTypeAliasText.TheAliasIsRemoved].Text;
  end
  else
  begin
    Result := Result + '.';
  end;
  if PreviewLines <> nil then
  begin
    Result := Result + sLineBreak + string.Join(sLineBreak, PreviewLines);
  end;
end;

class function TTypeAlias.InlineAlias(const ADeclaring: TTypeAliasSource; const AOthers: TArray<TTypeAliasSource>;
  const APosition: TTextPosition; const ALookup: TTypeAliasLookup; out AResult: TTypeAliasResult;
  out AReason: string): Boolean;
var
  mTarget: TInlineAliasTarget;
  mInlining: TInlining;
begin
  Result := False;
  AResult := Default(TTypeAliasResult);
  if not InlineTarget(ADeclaring.Text, ADeclaring.Tree, APosition, mTarget, AReason) then
  begin
    Exit;
  end;
  mInlining := TInlining.Create(ADeclaring, ALookup, mTarget);
  AReason := mInlining.ChangesIssue(AOthers);
  AResult := mInlining.Outcome;
  if (AReason = '') and Finish(mInlining.Changes, AResult, AReason) then
  begin
    AResult.Preview := mInlining.PreviewText(AResult);
    Result := True;
  end;
end;

end.
