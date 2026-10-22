unit Atlas.Common.Rules.Builtin.Components;

// Prüfregeln für VCL-Komponenten (#55, Teil A: alles innerhalb einer Unit):
//   component-missing-inherited          Loaded, Paint, CreateParams … ohne inherited
//   component-default-mismatch           default passt nicht zum Wert im Konstruktor
//   component-missing-free-notification  Komponentenreferenz ohne FreeNotification
//   component-setter-without-invalidate  Setter eines in Paint gelesenen Felds ohne Invalidate
//   component-fixed-pixels               feste Pixelwerte in Paint/Resize ohne ScaleValue
//   component-hardcoded-color            RGB-Literale und TColor-Casts in Paint
//   missing-inherited                    Konstruktor, Destroy, AfterConstruction
//                                        oder BeforeDestruction ohne inherited, für
//                                        alle Klassen (#919); Destroy von
//                                        Komponenten meldet nur
//                                        component-missing-inherited
//   message-handler-without-inherited    Methode mit "message WM_…"/"CM_…" ohne inherited,
//                                        DefaultHandler, DefWindowProc oder CallWindowProc
//                                        (#949); Nachrichten aus "swallow" und Handler, die
//                                        Msg.Result selbst setzen, bleiben still
//
// Geprüft werden nur Klassen, deren Vorfahrenkette (Datei, Symbolindex) eine
// bekannte VCL-Basisklasse erreicht. Teil B (nicht registriert, Design-Time-Units
// in Runtime-Packages) braucht Package-Dateien und folgt getrennt.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TComponentMissingInheritedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TComponentDefaultMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TComponentMissingFreeNotificationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TComponentSetterWithoutInvalidateRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TComponentFixedPixelsRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TComponentHardcodedColorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TMissingInheritedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option methods.</summary>
    class function DefaultMethods: TArray<string>; static;
  end;

  TMessageHandlerWithoutInheritedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option swallow: WM_ERASEBKGND.</summary>
    class function DefaultSwallow: TArray<string>; static;
    /// <summary>Folge für die Meldung: was ohne inherited bei der Nachricht AMessage wegfällt.</summary>
    class function Consequence(const AMessage: string): string; static;
  end;

procedure RegisterComponentRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Text.Lines;

const
  // Bekannte VCL-Basisklassen; erreicht die Vorfahrenkette eine davon, gilt die Klasse
  // als Komponente, auch wenn RTL und VCL nicht im Index stehen.
  ComponentBases: array[0..21] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TCustomPanel', 'TPanel', 'TCustomForm', 'TForm', 'TCustomFrame', 'TFrame',
    'TDataModule', 'TScrollingWinControl', 'TCustomListBox', 'TCustomEdit', 'TCustomComboBox',
    'TButtonControl', 'TCustomLabel', 'TImage', 'TDataSource', 'TDataSet', 'TCustomImageList');
  // Methoden, die im Nachfahren inherited aufrufen müssen.
  InheritedMethods: array[0..6] of string = ('Loaded', 'CreateParams', 'CreateWnd', 'Notification',
    'SetParent', 'Destroy', 'Paint');
  // RTL- und VCL-Klassen mit eigenem Konstruktor, auch wenn sie nicht im Index stehen (#919).
  ConstructorBases: array[0..13] of string = ('TThread', 'TStrings', 'TStringList', 'TList', 'TObjectList',
    'TDictionary', 'TObjectDictionary', 'TQueue', 'TStack', 'TStream', 'TFileStream', 'TMemoryStream',
    'TStringStream', 'TInterfacedPersistent');
  // Methoden, in denen Pixelwerte und Farben geprüft werden.
  PaintMethods: array[0..1] of string = ('Paint', 'Resize');
  // Aufrufe, deren Argumente schon skaliert werden.
  ScaleCalls: array[0..5] of string = ('ScaleValue', 'MulDiv', 'ScaleX', 'ScaleY', 'ScaleRect', 'ScaleSize');
  // Aufrufe, die ein Neuzeichnen veranlassen.
  RepaintCalls: array[0..6] of string = ('Invalidate', 'Repaint', 'Refresh', 'Update', 'Changed', 'Change',
    'InvalidateRect');
  // Zuweisungen an diese Eigenschaften sind keine Pixelwerte.
  NonPixelTargets: array[0..6] of string = ('Size', 'Color', 'Tag', 'Style', 'Mode', 'Charset', 'Orientation');

type
  /// <summary>Eine Klasse der Datei.</summary>
  TClassInfo = record
    Name: string;
    Body: TSyntaxNode;
  end;

  /// <summary>Eine Methodenimplementierung TKlasse.Methode.</summary>
  TMethodImpl = record
    ClassName: string;
    MethodName: string;
    Decl: TSyntaxNode;
    Block: TSyntaxNode;
  end;

  /// <summary>Eine Eigenschaft mit read/write/default aus den Token.</summary>
  TPropertyInfo = record
    Name: string;
    NameToken: TPascalToken;
    TypeName: string;
    ReadName: string;
    WriteName: string;
    HasDefault: Boolean;
    DefaultFirst: TPascalToken;
    DefaultLast: TPascalToken;
    DefaultText: string;
  end;

  /// <summary>Klassen, Implementierungen und Vorfahren der geprüften Datei.</summary>
  TComponentModel = class
  private
    FContext: TRuleContext;
    FAncestry: TAncestry;
    FClasses: TList<TClassInfo>;
    FMethods: TList<TMethodImpl>;
    FLineBreak: string;
    procedure Collect(ANode: TSyntaxNode);
  public
    /// <summary>ALocal ist der Index der Datei (TRuleDerived.UnitIndex). Das Modell liest aus AContext
    /// nur Tree und Text; es wird über den Ableitungscache von allen Komponentenregeln geteilt.</summary>
    constructor Create(const AContext: TRuleContext; const ALocal: TUnitIndex);
    destructor Destroy; override;
    function IsComponent(const AClassName: string): Boolean;
    function FindMethod(const AClassName, AMethodName: string; out AMethod: TMethodImpl): Boolean;
    function DeclaredWith(const AClass: TClassInfo; const AMethodName, ADirective: string): Boolean;
    function Properties(const AClass: TClassInfo): TArray<TPropertyInfo>;
    function HasToken(ANode: TSyntaxNode; const AWords: array of string): Boolean;
    function NodeText(ANode: TSyntaxNode): string;
    function NameToken(const AMethod: TMethodImpl; out AToken: TPascalToken): Boolean;
    function InsertAfterBegin(ABlock: TSyntaxNode; const AText: string; out AEdit: TRuleEdit): Boolean;
    function InsertBeforeEnd(ABlock: TSyntaxNode; const AText: string; out AEdit: TRuleEdit): Boolean;
    property Classes: TList<TClassInfo> read FClasses;
    property Methods: TList<TMethodImpl> read FMethods;
  end;

function IsIn(const AText: string; const AWords: array of string): Boolean;
var
  Word: string;
begin
  for Word in AWords do
    if SameText(AText, Word) then
      Exit(True);
  Result := False;
end;

{ TComponentModel }

constructor TComponentModel.Create(const AContext: TRuleContext; const ALocal: TUnitIndex);
begin
  inherited Create;
  FContext := AContext;
  // Bricht den Referenzzyklus Cache -> Modell -> Kontext -> Cache.
  FContext.Derived := nil;
  FAncestry := TAncestry.Create(AContext.Index, ALocal);
  FClasses := TList<TClassInfo>.Create;
  FMethods := TList<TMethodImpl>.Create;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
  Collect(AContext.Tree.Root);
end;

destructor TComponentModel.Destroy;
begin
  FMethods.Free;
  FClasses.Free;
  FAncestry.Free;
  inherited;
end;

procedure TComponentModel.Collect(ANode: TSyntaxNode);
begin
  // Iterativ (Bericht M1).
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    var
      Dot: Integer;
      Info: TClassInfo;
      Method: TMethodImpl;
    begin
      Result := True;
      if AVisited.Kind = TSyntaxKind.TypeDecl then
      begin
        Info.Name := AVisited.Name;
        Info.Body := AVisited.FindChild(TSyntaxKind.ClassType);
        if Info.Body <> nil then
          FClasses.Add(Info);
      end
      else if AVisited.Kind = TSyntaxKind.RoutineDecl then
      begin
        Dot := LastDelimiter('.', AVisited.Name);
        Method.Block := AVisited.FindChild(TSyntaxKind.Block);
        if (Dot > 0) and (Method.Block <> nil) then
        begin
          Method.ClassName := Copy(AVisited.Name, 1, Dot - 1);
          if Pos('<', Method.ClassName) > 0 then
            Method.ClassName := Copy(Method.ClassName, 1, Pos('<', Method.ClassName) - 1);
          Method.MethodName := Copy(AVisited.Name, Dot + 1, MaxInt);
          Method.Decl := AVisited;
          FMethods.Add(Method);
        end;
        // Lokale Routinen gehören nicht zur Klasse.
        Result := False;
      end;
    end);
end;

function TComponentModel.IsComponent(const AClassName: string): Boolean;
var
  Name: string;
  Depth: Integer;
begin
  Name := AClassName;
  Depth := 0;
  while (Name <> '') and (Depth < 64) do
  begin
    if IsIn(Name, ComponentBases) then
      Exit(True);
    if SameText(Name, 'TObject') then
      Break;
    Name := FAncestry.ParentOf(Name);
    Inc(Depth);
  end;
  Result := False;
end;

function TComponentModel.FindMethod(const AClassName, AMethodName: string; out AMethod: TMethodImpl): Boolean;
var
  Method: TMethodImpl;
begin
  for Method in FMethods do
    if SameText(Method.ClassName, AClassName) and SameText(Method.MethodName, AMethodName) then
    begin
      AMethod := Method;
      Exit(True);
    end;
  Result := False;
end;

function TComponentModel.DeclaredWith(const AClass: TClassInfo; const AMethodName, ADirective: string): Boolean;
var
  Index, Inner: Integer;
  Header: TSyntaxNode;
begin
  for Index := 0 to AClass.Body.ChildCount - 1 do
  begin
    Header := AClass.Body[Index];
    if (Header.Kind <> TSyntaxKind.RoutineHeader) or not SameText(Header.Name, AMethodName) then
      Continue;
    for Inner := 0 to Header.ChildCount - 1 do
      if (Header[Inner].Kind = TSyntaxKind.Directive) and SameText(Header[Inner].Name, ADirective) then
        Exit(True);
  end;
  Result := False;
end;

function TComponentModel.Properties(const AClass: TClassInfo): TArray<TPropertyInfo>;
var
  Index, TokenIndex: Integer;
  Decl, TypeRef: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  Token: TPascalToken;
  Info: TPropertyInfo;
  Mode: string;
  Count: Integer;
begin
  Result := nil;
  Tokens := FContext.Tree.Tokens;
  for Index := 0 to AClass.Body.ChildCount - 1 do
  begin
    Decl := AClass.Body[Index];
    if Decl.Kind <> TSyntaxKind.PropertyDecl then
      Continue;
    Info := Default(TPropertyInfo);
    Info.Name := Decl.Name;
    TypeRef := Decl.FindChild(TSyntaxKind.TypeReference);
    if TypeRef <> nil then
      Info.TypeName := TypeRef.Name;
    Mode := '';
    Count := 0;
    for TokenIndex := 0 to High(Tokens) do
    begin
      Token := Tokens[TokenIndex];
      if Token.Offset < Decl.StartOffset then
        Continue;
      if Token.Offset >= Decl.EndOffset then
        Break;
      if Token.Kind = TPascalTokenKind.Comment then
        Continue;
      if (Info.NameToken.Text = '') and (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, Decl.Name) then
        Info.NameToken := Token;
      if Token.IsSymbol(';') then
        Mode := ''
      else if IsIn(Token.Text, ['read', 'write', 'default', 'stored', 'nodefault', 'implements', 'index']) then
      begin
        Mode := LowerCase(Token.Text);
        Count := 0;
      end
      else if Mode = 'read' then
      begin
        if Count = 0 then
          Info.ReadName := Token.Text;
        Inc(Count);
      end
      else if Mode = 'write' then
      begin
        if Count = 0 then
          Info.WriteName := Token.Text;
        Inc(Count);
      end
      else if Mode = 'default' then
      begin
        if Count = 0 then
          Info.DefaultFirst := Token;
        Info.DefaultLast := Token;
        Info.DefaultText := Info.DefaultText + Token.Text;
        Info.HasDefault := True;
        Inc(Count);
      end;
    end;
    // Mehrteilige Feldzugriffe (FData.Wert) sind kein einfaches Feld.
    if Pos('.', Info.ReadName) > 0 then
      Info.ReadName := '';
    Result := Result + [Info];
  end;
end;

function TComponentModel.HasToken(ANode: TSyntaxNode; const AWords: array of string): Boolean;
var
  Token: TPascalToken;
begin
  for Token in FContext.Tree.Tokens do
  begin
    if Token.Offset < ANode.StartOffset then
      Continue;
    if Token.Offset >= ANode.EndOffset then
      Break;
    if (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and IsIn(Token.Text, AWords) then
      Exit(True);
  end;
  Result := False;
end;

function TComponentModel.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TComponentModel.NameToken(const AMethod: TMethodImpl; out AToken: TPascalToken): Boolean;
var
  Header: TSyntaxNode;
  Token: TPascalToken;
begin
  Header := AMethod.Decl.FindChild(TSyntaxKind.RoutineHeader);
  Result := False;
  if Header = nil then
    Exit;
  // Der letzte passende Bezeichner im Kopf vor der Parameterliste.
  for Token in FContext.Tree.Tokens do
  begin
    if Token.Offset < Header.StartOffset then
      Continue;
    if (Token.Offset >= Header.EndOffset) or Token.IsSymbol('(') or Token.IsSymbol(';') or Token.IsSymbol(':') then
      Break;
    if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, AMethod.MethodName) then
    begin
      AToken := Token;
      Result := True;
    end;
  end;
end;

function TComponentModel.InsertAfterBegin(ABlock: TSyntaxNode; const AText: string; out AEdit: TRuleEdit): Boolean;
var
  Token: TPascalToken;
  Indent: Integer;
begin
  Result := False;
  for Token in FContext.Tree.Tokens do
    if (Token.Offset = ABlock.StartOffset) and Token.IsKeyword('begin') then
    begin
      if ABlock.ChildCount > 0 then
        Indent := ABlock[0].StartPos.Character
      else
        Indent := Token.StartPos.Character + 2;
      AEdit := TRuleEdit.Create(TTextRange.Create(Token.EndPos, Token.EndPos),
        FLineBreak + StringOfChar(' ', Indent) + AText);
      Exit(True);
    end;
end;

function TComponentModel.InsertBeforeEnd(ABlock: TSyntaxNode; const AText: string; out AEdit: TRuleEdit): Boolean;
var
  Token, Last, Begin_: TPascalToken;
  Found: Boolean;
  Indent: Integer;
  Prefix: string;
begin
  Result := False;
  Found := False;
  Begin_ := Default(TPascalToken);
  Last := Default(TPascalToken);
  // Letztes Token vor dem abschließenden end des Blocks.
  for Token in FContext.Tree.Tokens do
  begin
    if Token.Offset < ABlock.StartOffset then
      Continue;
    if Token.Offset >= ABlock.EndOffset then
      Break;
    if Token.Kind = TPascalTokenKind.Comment then
      Continue;
    if Token.IsKeyword('end') and (Token.Offset + Length(Token.Text) = ABlock.EndOffset) then
      Break;
    if Begin_.Text = '' then
      Begin_ := Token;
    Last := Token;
    Found := True;
  end;
  if not Found then
    Exit;
  if ABlock.ChildCount > 0 then
    Indent := ABlock[0].StartPos.Character
  else
    Indent := Begin_.StartPos.Character + 2;
  // Fehlt das Semikolon nach der letzten Anweisung, kommt es dazu.
  if Last.IsSymbol(';') or Last.IsKeyword('begin') then
    Prefix := ''
  else
    Prefix := ';';
  AEdit := TRuleEdit.Create(TTextRange.Create(Last.EndPos, Last.EndPos),
    Prefix + FLineBreak + StringOfChar(' ', Indent) + AText);
  Result := True;
end;

/// <summary>Modell der Datei, je Lauf einmal gebaut (Review P-03); gehört ACache, nie freigeben.
/// False ohne Syntaxbaum.</summary>
function Prepare(const ACache: IRuleDerivedCache; const AContext: TRuleContext; out AModel: TComponentModel): Boolean;
var
  Context: TRuleContext;
  Local: TUnitIndex;
begin
  AModel := nil;
  Result := AContext.Tree <> nil;
  if not Result then
    Exit;
  // const-Parameter dürfen anonyme Methoden nicht erfassen (E2555): lokale Kopien.
  Context := AContext;
  Local := TRuleDerived.UnitIndex(ACache, AContext);
  AModel := TRuleDerived.Get<TComponentModel>(ACache, 'components.model',
    function: TComponentModel
    begin
      Result := TComponentModel.Create(Context, Local);
    end);
end;

{ TComponentMissingInheritedRule }

function TComponentMissingInheritedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-missing-inherited', TRuleSeverity.Warning,
    'Überschriebene Komponentenmethode ruft inherited nicht auf');
end;

procedure TComponentMissingInheritedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Info: TClassInfo;
  Method: TMethodImpl;
  Token: TPascalToken;
  Edit: TRuleEdit;
  Inserted: Boolean;
  Confidence: TRuleConfidence;
  Message: string;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) then
    Exit;
  for Info in Model.Classes do
  begin
    if not Model.IsComponent(Info.Name) then
      Continue;
    for Method in Model.Methods do
    begin
      if not SameText(Method.ClassName, Info.Name) or not IsIn(Method.MethodName, InheritedMethods) or
        not Model.DeclaredWith(Info, Method.MethodName, 'override') or
        Model.HasToken(Method.Block, ['inherited']) or not Model.NameToken(Method, Token) then
        Continue;
      // TCustomControl.Paint zeichnet nur den Rahmen im Designer; oft bewusst weggelassen.
      if SameText(Method.MethodName, 'Paint') then
        Confidence := TRuleConfidence.Low
      else
        Confidence := TRuleConfidence.High;
      // Im Destruktor zuletzt, sonst zuerst.
      if SameText(Method.MethodName, 'Destroy') then
        Inserted := Model.InsertBeforeEnd(Method.Block, 'inherited;', Edit)
      else
        Inserted := Model.InsertAfterBegin(Method.Block, 'inherited;', Edit);
      Message := Format('%s.%s ruft inherited nicht auf; die VCL erledigt dort eigene Arbeit',
        [Info.Name, Method.MethodName]);
      if Inserted then
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), Message, Confidence,
          [TRuleFix.Create('"inherited;" einfügen', [Edit])])
      else
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), Message, Confidence);
    end;
  end;
end;

{ TComponentDefaultMismatchRule }

function TComponentDefaultMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-default-mismatch', TRuleSeverity.Warning,
    'default-Angabe stimmt nicht mit dem Wert im Konstruktor überein');
end;

/// <summary>Zuweisung an AField im Block (Feld oder Self.Feld); der zugewiesene Ausdruck.</summary>
function FindAssignment(ANode: TSyntaxNode; const AField: string; out AValue: TSyntaxNode): Boolean;
var
  Field: string;
  Found: TSyntaxNode;
begin
  Field := AField;
  // Iterativ (Bericht M1); out-Parameter lassen sich nicht in der anonymen Methode verwenden.
  Found := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    var
      Target: TSyntaxNode;
    begin
      if (AVisited.Kind = TSyntaxKind.AssignStatement) and (AVisited.ChildCount = 2) and
        SameText(AVisited.Name, Field) then
      begin
        Target := AVisited[0];
        if (Target.Kind = TSyntaxKind.Identifier) or ((Target.Kind = TSyntaxKind.MemberAccess) and
          (Target.ChildCount = 1) and (Target[0].Kind = TSyntaxKind.Identifier) and
          SameText(Target[0].Name, 'Self')) then
          Exit(TSyntaxSearchStep.Found);
      end;
      if AVisited.Kind = TSyntaxKind.AnonymousMethod then
        Exit(TSyntaxSearchStep.Skip);
      Result := TSyntaxSearchStep.Descend;
    end);
  Result := Found <> nil;
  if Result then
    AValue := Found[1];
end;

/// <summary>Gleicher Wert? Zahlen werden verglichen ($-Hex wie dezimal), sonst der Text.</summary>
function SameValue(const A, B: string): Boolean;
var
  NumberA, NumberB: Int64;
begin
  if TryStrToInt64(A, NumberA) and TryStrToInt64(B, NumberB) then
    Result := NumberA = NumberB
  else
    Result := SameText(StringReplace(A, ' ', '', [rfReplaceAll]), StringReplace(B, ' ', '', [rfReplaceAll]));
end;

procedure TComponentDefaultMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Info: TClassInfo;
  Prop: TPropertyInfo;
  Ctor: TMethodImpl;
  Value: TSyntaxNode;
  ValueText: string;
  Range: TTextRange;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) then
    Exit;
  for Info in Model.Classes do
  begin
    if not Model.IsComponent(Info.Name) or not Model.FindMethod(Info.Name, 'Create', Ctor) then
      Continue;
    for Prop in Model.Properties(Info) do
    begin
      if not Prop.HasDefault or (Prop.ReadName = '') or not FindAssignment(Ctor.Block, Prop.ReadName, Value) then
        Continue;
      // Nur feste Werte geben eine Aussage.
      if not (Value.Kind in [TSyntaxKind.Literal, TSyntaxKind.Identifier, TSyntaxKind.UnaryExpr]) then
        Continue;
      ValueText := Model.NodeText(Value);
      if SameValue(ValueText, Prop.DefaultText) then
        Continue;
      Range := TTextRange.Create(Prop.DefaultFirst.StartPos, Prop.DefaultLast.EndPos);
      AReport.Add(Range, Format('"%s" hat default %s, der Konstruktor setzt %s aber auf %s; der Wert wird ' +
        'dann nicht in der DFM gespeichert oder falsch geladen', [Prop.Name, Prop.DefaultText, Prop.ReadName,
        ValueText]), TRuleConfidence.High,
        [TRuleFix.Create(Format('default auf %s ändern', [ValueText]), [TRuleEdit.Create(Range, ValueText)])]);
    end;
  end;
end;

{ TComponentMissingFreeNotificationRule }

function TComponentMissingFreeNotificationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-missing-free-notification', TRuleSeverity.Warning,
    'Komponentenreferenz ohne FreeNotification');
end;

/// <summary>Name des letzten Parameters der Implementierung.</summary>
function LastParameter(const AMethod: TMethodImpl): string;
var
  Header, Params: TSyntaxNode;
begin
  Result := '';
  Header := AMethod.Decl.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
    Exit;
  Params := Header.FindChild(TSyntaxKind.Parameters);
  if (Params <> nil) and (Params.ChildCount > 0) then
    Result := Params[Params.ChildCount - 1].Name;
end;

procedure TComponentMissingFreeNotificationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Message = '"%s" verweist auf eine fremde Komponente ohne FreeNotification; wird sie freigegeben, ' +
    'bleibt ein ungültiger Zeiger zurück';
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Info: TClassInfo;
  Prop: TPropertyInfo;
  Setter, Ctor: TMethodImpl;
  Value: TSyntaxNode;
  Edit: TRuleEdit;
  Parameter: string;
  Range: TTextRange;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) then
    Exit;
  for Info in Model.Classes do
  begin
    if not Model.IsComponent(Info.Name) then
      Continue;
    for Prop in Model.Properties(Info) do
    begin
      if (Prop.TypeName = '') or (Prop.WriteName = '') or (Prop.NameToken.Text = '') or
        not Model.IsComponent(Prop.TypeName) then
        Continue;
      // Eigene Unterkomponenten (im Konstruktor erzeugt) brauchen keine Benachrichtigung.
      if (Prop.ReadName <> '') and Model.FindMethod(Info.Name, 'Create', Ctor) and
        FindAssignment(Ctor.Block, Prop.ReadName, Value) and ContainsText(Model.NodeText(Value), '.Create') then
        Continue;
      Range := TTextRange.Create(Prop.NameToken.StartPos, Prop.NameToken.EndPos);
      if not Model.FindMethod(Info.Name, Prop.WriteName, Setter) then
      begin
        // write auf ein Feld: es gibt keinen Setter, in dem FreeNotification stehen könnte.
        if SameText(Prop.WriteName, Prop.ReadName) then
          AReport.Add(Range, Format(Message, [Prop.Name]), TRuleConfidence.Medium);
        Continue;
      end;
      if Model.HasToken(Setter.Block, ['FreeNotification']) then
        Continue;
      Parameter := LastParameter(Setter);
      if (Parameter <> '') and Model.InsertBeforeEnd(Setter.Block,
        Format('if %s <> nil then', [Parameter]) + ' ' + Format('%s.FreeNotification(Self);', [Parameter]), Edit) then
        AReport.Add(Range, Format(Message, [Prop.Name]), TRuleConfidence.Medium,
          [TRuleFix.Create('FreeNotification im Setter ergänzen', [Edit])])
      else
        AReport.Add(Range, Format(Message, [Prop.Name]), TRuleConfidence.Medium);
    end;
  end;
end;

{ TComponentSetterWithoutInvalidateRule }

function TComponentSetterWithoutInvalidateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-setter-without-invalidate', TRuleSeverity.Hint,
    'Setter ändert ein in Paint gelesenes Feld ohne Invalidate');
end;

procedure TComponentSetterWithoutInvalidateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Info: TClassInfo;
  Prop: TPropertyInfo;
  Setter, Paint: TMethodImpl;
  Value: TSyntaxNode;
  Token: TPascalToken;
  Edit: TRuleEdit;
  Message: string;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) then
    Exit;
  for Info in Model.Classes do
  begin
    if not Model.IsComponent(Info.Name) or not Model.FindMethod(Info.Name, 'Paint', Paint) then
      Continue;
    for Prop in Model.Properties(Info) do
    begin
      if (Prop.ReadName = '') or not Model.FindMethod(Info.Name, Prop.WriteName, Setter) or
        not FindAssignment(Setter.Block, Prop.ReadName, Value) or
        not Model.HasToken(Paint.Block, [Prop.ReadName, Prop.Name]) or
        Model.HasToken(Setter.Block, RepaintCalls) or not Model.NameToken(Setter, Token) then
        Continue;
      Message := Format('%s ändert %s, das Paint liest, ohne Invalidate; die Anzeige bleibt veraltet',
        [Setter.MethodName, Prop.ReadName]);
      if Model.InsertBeforeEnd(Setter.Block, 'Invalidate;', Edit) then
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), Message, TRuleConfidence.Medium,
          [TRuleFix.Create('"Invalidate;" einfügen', [Edit])])
      else
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), Message, TRuleConfidence.Medium);
    end;
  end;
end;

{ TComponentFixedPixelsRule }

function TComponentFixedPixelsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-fixed-pixels', TRuleSeverity.Warning,
    'Feste Pixelwerte in Paint oder Resize ohne Skalierung');
end;

/// <summary>Ganze Dezimalzahl außer 0, 1 und -1?</summary>
function IsPixelLiteral(ANode: TSyntaxNode): Boolean;
var
  Value: Integer;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and (ANode.Name <> '') and CharInSet(ANode.Name[1], ['0'..'9']) and
    TryStrToInt(ANode.Name, Value) and (Value > 1);
end;

/// <summary>Skaliert der Aufruf seinen Wert? Neben ScaleValue & Co. auch eigene Helfer wie Scale(3) oder
/// ScaleDpi(3), deren Name mit Scale beginnt (#647).</summary>
function IsScaleCall(const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  if LastDelimiter('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  Result := IsIn(Name, ScaleCalls) or StartsText('Scale', Name);
end;

/// <summary>Steht der Wert in einem Zusammenhang, der kein Pixelwert ist oder schon skaliert?</summary>
function Excluded(ANode: TSyntaxNode): Boolean;
var
  Parent, Child: TSyntaxNode;
begin
  Child := ANode;
  Parent := ANode.Parent;
  while Parent <> nil do
  begin
    case Parent.Kind of
      TSyntaxKind.Call:
        if IsScaleCall(Parent.Name) or IsIn(Parent.Name, ['RGB', 'TColor', 'Sleep', 'Inc', 'Dec']) then
          Exit(True);
      TSyntaxKind.BinaryExpr:
        if (Child = ANode) and IsIn(Parent.Name, ['*', '/', 'div', 'mod', 'shl', 'shr', 'and', 'or', 'xor']) then
          Exit(True);
      TSyntaxKind.IndexAccess, TSyntaxKind.CaseItem, TSyntaxKind.ForStatement, TSyntaxKind.SetConstructor:
        if Child = ANode then
          Exit(True);
      TSyntaxKind.AssignStatement:
        Exit(IsIn(Parent.Name, NonPixelTargets));
      TSyntaxKind.Block, TSyntaxKind.RoutineDecl:
        Exit(False);
    end;
    Child := Parent;
    Parent := Parent.Parent;
  end;
  Result := False;
end;

procedure CollectPixels(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  List: TList<TSyntaxNode>;
begin
  List := AList;
  // Iterativ (Bericht M1).
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      Result := AVisited.Kind <> TSyntaxKind.AnonymousMethod;
      if Result and IsPixelLiteral(AVisited) and not Excluded(AVisited) then
        List.Add(AVisited);
    end);
end;

procedure TComponentFixedPixelsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Method: TMethodImpl;
  Literals: TList<TSyntaxNode>;
  Index, Last: Integer;
  Edits: TArray<TRuleEdit>;
  Literal: TSyntaxNode;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) then
    Exit;
  Literals := TList<TSyntaxNode>.Create;
  try
    for Method in Model.Methods do
    begin
      if not IsIn(Method.MethodName, PaintMethods) or not Model.IsComponent(Method.ClassName) then
        Continue;
      Literals.Clear;
      CollectPixels(Method.Block, Literals);
      // Ein Treffer je Ausdruck (z. B. Rect(0, 0, 16, 16)), nicht je Zahl.
      Index := 0;
      while Index < Literals.Count do
      begin
        Last := Index;
        while (Last + 1 < Literals.Count) and (Literals[Last + 1].Parent = Literals[Index].Parent) do
          Inc(Last);
        Edits := nil;
        while Index <= Last do
        begin
          Literal := Literals[Index];
          Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Literal.StartPos, Literal.EndPos),
            'ScaleValue(' + Literal.Name + ')')];
          Inc(Index);
        end;
        AReport.Add(TTextRange.Create(Literals[Last - Length(Edits) + 1].StartPos, Literals[Last].EndPos),
          Format('Fester Pixelwert in %s: bei mehr als 96 dpi zu klein; ScaleValue verwenden',
          [Method.MethodName]), TRuleConfidence.Medium, [TRuleFix.Create('Mit ScaleValue skalieren', Edits)]);
      end;
    end;
  finally
    Literals.Free;
  end;
end;

{ TComponentHardcodedColorRule }

function TComponentHardcodedColorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-hardcoded-color', TRuleSeverity.Hint,
    'Feste Farbe in Paint statt Systemfarbe oder StyleServices');
end;

procedure CollectColors(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  List: TList<TSyntaxNode>;
begin
  List := AList;
  // Iterativ (Bericht M1).
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      Result := AVisited.Kind <> TSyntaxKind.AnonymousMethod;
      if not Result then
        Exit;
      // RGB(…) und TColor(…)
      if (AVisited.Kind = TSyntaxKind.Call) and IsIn(AVisited.Name, ['RGB', 'TColor']) then
      begin
        List.Add(AVisited);
        Exit(False);
      end;
      // $00BBGGRR oder eine Zahl, die einer …Color-Eigenschaft zugewiesen wird
      if (AVisited.Kind = TSyntaxKind.Literal) and (AVisited.Name <> '') and
        CharInSet(AVisited.Name[1], ['$', '0'..'9']) and (AVisited.Parent <> nil) and
        (AVisited.Parent.Kind = TSyntaxKind.AssignStatement) and EndsText('Color', AVisited.Parent.Name) then
        List.Add(AVisited);
    end);
end;

procedure TComponentHardcodedColorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Method: TMethodImpl;
  Colors: TList<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) then
    Exit;
  Colors := TList<TSyntaxNode>.Create;
  try
    for Method in Model.Methods do
    begin
      if not SameText(Method.MethodName, 'Paint') or not Model.IsComponent(Method.ClassName) then
        Continue;
      Colors.Clear;
      CollectColors(Method.Block, Colors);
      for Node in Colors do
        AReport.Add(TTextRange.Create(Node.StartPos, Node.EndPos), 'Feste Farbe in Paint: passt nicht zu ' +
          'VCL-Styles; Systemfarben (clBtnFace …) oder StyleServices.GetSystemColor verwenden',
          TRuleConfidence.Medium);
    end;
  finally
    Colors.Free;
  end;
end;

{ TMissingInheritedRule }

function TMissingInheritedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('missing-inherited', TRuleSeverity.Warning,
    'Konstruktor oder Destruktor ohne inherited');
end;

class function TMissingInheritedRule.DefaultMethods: TArray<string>;
begin
  Result := ['Create', 'Destroy', 'AfterConstruction', 'BeforeDestruction'];
end;

/// <summary>Direkter Vorfahr laut Klassendeklaration; '' ohne Angabe (TObject).</summary>
function DeclaredParent(const AClass: TClassInfo): string;
begin
  Result := '';
  if (AClass.Body.ChildCount > 0) and (AClass.Body[0].Kind = TSyntaxKind.TypeReference) then
    Result := AClass.Body[0].Name;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
end;

/// <summary>Kopf der Methode AName in der Klassendeklaration, sonst nil.</summary>
function ClassHeader(const AClass: TClassInfo; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to AClass.Body.ChildCount - 1 do
    if (AClass.Body[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(AClass.Body[Index].Name, AName) then
      Exit(AClass.Body[Index]);
  Result := nil;
end;

procedure TMissingInheritedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Info: TClassInfo;
  Method: TMethodImpl;
  Token: TPascalToken;
  Edit: TRuleEdit;
  Methods, Constructors: TArray<string>;
  Parent, Message, Statement, Source: string;
  Header: TSyntaxNode;
  Index: Integer;
  IsConstructor, AtEnd, Inserted: Boolean;

  // Legt ein Vorfahr (bis TObject) eigene Felder im Konstruktor an?
  function AncestorConstructs(const AName: string): Boolean;
  var
    Name: string;
    Depth: Integer;
  begin
    Name := AName;
    Depth := 0;
    while (Name <> '') and not SameText(Name, 'TObject') and (Depth < 64) do
    begin
      if IsIn(Name, ComponentBases) or IsIn(Name, ConstructorBases) or Model.FAncestry.HasConstructor(Name) then
        Exit(True);
      Name := Model.FAncestry.ParentOf(Name);
      Inc(Depth);
    end;
    Result := False;
  end;

  // Ruft der Rumpf einen anderen Konstruktor derselben Klasse auf (Create(nil), Self.Create(nil))?
  function CallsOwnConstructor(ANode: TSyntaxNode): Boolean;
  var
    Target: TSyntaxNode;
    Child: Integer;
  begin
    Result := False;
    if ANode.Kind = TSyntaxKind.AnonymousMethod then
      Exit;
    if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) then
    begin
      Target := ANode[0];
      if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
        Target := Target[0];
      if ((Target.Kind = TSyntaxKind.Identifier) or ((Target.Kind = TSyntaxKind.MemberAccess) and
        (Target.ChildCount = 1) and (Target[0].Kind = TSyntaxKind.Identifier) and
        SameText(Target[0].Name, 'Self'))) and IsIn(Target.Name, Constructors) then
        Exit(True);
    end;
    for Child := 0 to ANode.ChildCount - 1 do
      if CallsOwnConstructor(ANode[Child]) then
        Exit(True);
  end;

begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) then
    Exit;
  Methods := TRuleOptions.Strings(AContext.Options, 'methods', DefaultMethods);
  for Info in Model.Classes do
  begin
    Parent := DeclaredParent(Info);
    // Ohne Vorfahr erbt die Klasse von TObject: dort gibt es nichts aufzurufen.
    if (Parent = '') or SameText(Parent, 'TObject') then
      Continue;
    Constructors := nil;
    for Index := 0 to Info.Body.ChildCount - 1 do
      if (Info.Body[Index].Kind = TSyntaxKind.RoutineHeader) and
        StartsText('constructor', TrimLeft(Model.NodeText(Info.Body[Index]))) then
        Constructors := Constructors + [Info.Body[Index].Name];
    for Method in Model.Methods do
    begin
      if not SameText(Method.ClassName, Info.Name) or Model.HasToken(Method.Block, ['inherited']) then
        Continue;
      Source := TrimLeft(Model.NodeText(Method.Decl));
      // Klassenkonstruktoren und Klassenmethoden haben kein inherited der Instanz.
      if StartsText('class ', Source) then
        Continue;
      IsConstructor := StartsText('constructor', Source);
      if IsConstructor then
      begin
        if not (IsIn(Method.MethodName, Methods) or (IsIn('Create', Methods) and
          StartsText('Create', Method.MethodName))) then
          Continue;
        if CallsOwnConstructor(Method.Block) or not AncestorConstructs(Parent) then
          Continue;
      end
      else
      begin
        if not IsIn(Method.MethodName, Methods) or not Model.DeclaredWith(Info, Method.MethodName, 'override') then
          Continue;
        // Komponenten: Destroy meldet component-missing-inherited (keine Doppelmeldung).
        if Model.IsComponent(Info.Name) and IsIn(Method.MethodName, InheritedMethods) then
          Continue;
      end;
      if not Model.NameToken(Method, Token) then
        Continue;
      AtEnd := SameText(Method.MethodName, 'Destroy') or SameText(Method.MethodName, 'BeforeDestruction') or
        (StartsText('destructor', Source));
      if AtEnd then
        Message := Format('%s ruft inherited nicht auf; die Felder von %s werden nie freigegeben.',
          [Method.MethodName, Parent])
      else if IsConstructor then
        Message := Format('%s ruft inherited nicht auf; die Felder von %s werden nie angelegt.',
          [Method.MethodName, Parent])
      else
        Message := Format('%s ruft inherited nicht auf; die Arbeit von %s nach dem Erzeugen entfällt.',
          [Method.MethodName, Parent]);
      // inherited; reicht die Parameter weiter. Ein eigener Konstruktor mit Parametern ohne override
      // ruft den des Vorfahren ohne Argumente.
      Statement := 'inherited;';
      Header := ClassHeader(Info, Method.MethodName);
      if IsConstructor and not Model.DeclaredWith(Info, Method.MethodName, 'override') and (Header <> nil) and
        (Pos('(', Model.NodeText(Header)) > 0) then
        Statement := 'inherited Create;';
      if AtEnd then
        Inserted := Model.InsertBeforeEnd(Method.Block, Statement, Edit)
      else
        Inserted := Model.InsertAfterBegin(Method.Block, Statement, Edit);
      if Inserted then
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), Message, TRuleConfidence.High,
          [TRuleFix.Create(Format('"%s" einfügen', [Statement]), [Edit])])
      else
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), Message, TRuleConfidence.High);
    end;
  end;
end;

{ TMessageHandlerWithoutInheritedRule }

function TMessageHandlerWithoutInheritedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('message-handler-without-inherited', TRuleSeverity.Warning,
    'Message-Handler ohne inherited');
end;

class function TMessageHandlerWithoutInheritedRule.DefaultSwallow: TArray<string>;
begin
  Result := ['WM_ERASEBKGND'];
end;

class function TMessageHandlerWithoutInheritedRule.Consequence(const AMessage: string): string;
var
  Name: string;
begin
  Name := UpperCase(Copy(AMessage, LastDelimiter('.', AMessage) + 1, MaxInt));
  if (Name = 'WM_SIZE') or (Name = 'WM_WINDOWPOSCHANGED') or (Name = 'WM_WINDOWPOSCHANGING') then
    Result := 'die VCL passt Ausrichtung und Anker nicht mehr an'
  else if (Name = 'WM_CLOSE') or (Name = 'WM_QUERYENDSESSION') then
    Result := 'das Fenster schließt nicht mehr'
  else if (Name = 'WM_PAINT') or (Name = 'WM_NCPAINT') or (Name = 'WM_PRINTCLIENT') then
    Result := 'die VCL zeichnet das Steuerelement nicht mehr'
  else if (Name = 'WM_KEYDOWN') or (Name = 'WM_KEYUP') or (Name = 'WM_CHAR') or (Name = 'WM_SYSKEYDOWN') or
    (Name = 'WM_SYSCHAR') or (Name = 'CM_DIALOGKEY') or (Name = 'CM_DIALOGCHAR') or (Name = 'CM_WANTSPECIALKEY') then
    Result := 'Tastatureingaben erreichen die Standardbehandlung nicht mehr'
  else if (Name = 'WM_SETFOCUS') or (Name = 'WM_KILLFOCUS') or (Name = 'CM_ENTER') or (Name = 'CM_EXIT') then
    Result := 'die Fokusbehandlung der VCL entfällt'
  else if StartsStr('WM_LBUTTON', Name) or StartsStr('WM_RBUTTON', Name) or StartsStr('WM_MBUTTON', Name) or
    (Name = 'WM_MOUSEMOVE') or (Name = 'WM_MOUSEWHEEL') or (Name = 'CM_MOUSEENTER') or (Name = 'CM_MOUSELEAVE') then
    Result := 'Mausereignisse wie OnClick und OnMouseDown entfallen'
  else if (Name = 'WM_DESTROY') or (Name = 'WM_NCDESTROY') then
    Result := 'die VCL räumt das Fenster nicht mehr auf'
  else if (Name = 'WM_DPICHANGED') or (Name = 'CM_PARENTFONTCHANGED') or (Name = 'CM_FONTCHANGED') or
    (Name = 'CM_STYLECHANGED') then
    Result := 'Schrift und Skalierung passen sich nicht mehr an'
  else if StartsStr('CM_', Name) then
    Result := 'die Standardbehandlung der VCL entfällt'
  else
    Result := 'die Standardbehandlung von Windows bzw. der VCL entfällt';
end;

procedure TMessageHandlerWithoutInheritedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Info: TClassInfo;
  Method: TMethodImpl;
  Token: TPascalToken;
  Edit: TRuleEdit;
  Swallow: TArray<string>;
  Parent, MessageName: string;
  Index: Integer;
  Header: TSyntaxNode;
  Match: TMatch;

  // Setzt der Rumpf "Msg.Result := …"? Dann beantwortet der Handler die Nachricht bewusst selbst
  // (MA_NOACTIVATE, HTCLIENT).
  function AnswersItself(ABlock: TSyntaxNode): Boolean;
  var
    Code: TArray<TPascalToken>;
    Token: TPascalToken;
    Index: Integer;
  begin
    Code := nil;
    for Token in AContext.Tree.Tokens do
      if (Token.Offset >= ABlock.StartOffset) and (Token.Offset < ABlock.EndOffset) and
        not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
        Code := Code + [Token];
    for Index := 1 to High(Code) - 1 do
      if Code[Index - 1].IsSymbol('.') and SameText(Code[Index].Text, 'Result') and Code[Index + 1].IsSymbol(':=') then
        Exit(True);
    Result := False;
  end;

begin
  Cache := TRuleDerived.Open(AContext);
  if not ContainsText(AContext.Text, 'message') or not Prepare(Cache, AContext, Model) then
    Exit;
  Swallow := TRuleOptions.Strings(AContext.Options, 'swallow', DefaultSwallow);
  for Info in Model.Classes do
  begin
    // Ohne Vorfahr behandelt TObject.DefaultHandler nichts.
    Parent := DeclaredParent(Info);
    if (Parent = '') or SameText(Parent, 'TObject') then
      Continue;
    for Index := 0 to Info.Body.ChildCount - 1 do
    begin
      Header := Info.Body[Index];
      if Header.Kind <> TSyntaxKind.RoutineHeader then
        Continue;
      Match := TRegEx.Match(Model.NodeText(Header), '\bmessage\s+([\w.]+)', [roIgnoreCase]);
      if not Match.Success then
        Continue;
      MessageName := Match.Groups[1].Value;
      if MatchText(Copy(MessageName, LastDelimiter('.', MessageName) + 1, MaxInt), Swallow) or
        not Model.FindMethod(Info.Name, Header.Name, Method) or (Method.Block = nil) or
        Model.HasToken(Method.Block, ['inherited', 'DefaultHandler', 'DefWindowProc', 'CallWindowProc']) or
        AnswersItself(Method.Block) or not Model.NameToken(Method, Token) then
        Continue;
      if Model.InsertAfterBegin(Method.Block, 'inherited;', Edit) then
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos),
          Format('%s ruft inherited nicht auf; %s.', [Method.MethodName, Consequence(MessageName)]),
          TRuleConfidence.Medium, [TRuleFix.Create('"inherited;" am Anfang einfügen', [Edit])])
      else
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos),
          Format('%s ruft inherited nicht auf; %s.', [Method.MethodName, Consequence(MessageName)]),
          TRuleConfidence.Medium);
    end;
  end;
end;

procedure RegisterComponentRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMissingInheritedRule.Create);
  ARegistry.Register(TMessageHandlerWithoutInheritedRule.Create);
  ARegistry.Register(TComponentMissingInheritedRule.Create);
  ARegistry.Register(TComponentDefaultMismatchRule.Create);
  ARegistry.Register(TComponentMissingFreeNotificationRule.Create);
  ARegistry.Register(TComponentSetterWithoutInvalidateRule.Create);
  ARegistry.Register(TComponentFixedPixelsRule.Create);
  ARegistry.Register(TComponentHardcodedColorRule.Create);
end;

end.
