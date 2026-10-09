unit Argus.Common.Rules.Builtin.Components;

// Prüfregeln für VCL-Komponenten (#55, Teil A: alles innerhalb einer Unit):
//   component-missing-inherited          Loaded, Paint, CreateParams … ohne inherited
//   component-default-mismatch           default passt nicht zum Wert im Konstruktor
//   component-missing-free-notification  Komponentenreferenz ohne FreeNotification
//   component-setter-without-invalidate  Setter eines in Paint gelesenen Felds ohne Invalidate
//   component-fixed-pixels               feste Pixelwerte in Paint/Resize ohne ScaleValue
//   component-hardcoded-color            RGB-Literale und TColor-Casts in Paint
//
// Geprüft werden nur Klassen, deren Vorfahrenkette (Datei, Symbolindex) eine
// bekannte VCL-Basisklasse erreicht. Teil B (nicht registriert, Design-Time-Units
// in Runtime-Packages) braucht Package-Dateien und folgt getrennt.

interface

uses
  System.SysUtils,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Registry;

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

procedure RegisterComponentRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Rules.Builtin.Inheritance;

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
    constructor Create(const AContext: TRuleContext);
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

constructor TComponentModel.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FContext := AContext;
  FAncestry := TAncestry.Create(AContext);
  FClasses := TList<TClassInfo>.Create;
  FMethods := TList<TMethodImpl>.Create;
  if Pos(#13#10, AContext.Text) > 0 then
    FLineBreak := #13#10
  else
    FLineBreak := #10;
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
var
  Index, Dot: Integer;
  Info: TClassInfo;
  Method: TMethodImpl;
begin
  if ANode.Kind = TSyntaxKind.TypeDecl then
  begin
    Info.Name := ANode.Name;
    Info.Body := ANode.FindChild(TSyntaxKind.ClassType);
    if Info.Body <> nil then
      FClasses.Add(Info);
  end
  else if ANode.Kind = TSyntaxKind.RoutineDecl then
  begin
    Dot := LastDelimiter('.', ANode.Name);
    Method.Block := ANode.FindChild(TSyntaxKind.Block);
    if (Dot > 0) and (Method.Block <> nil) then
    begin
      Method.ClassName := Copy(ANode.Name, 1, Dot - 1);
      if Pos('<', Method.ClassName) > 0 then
        Method.ClassName := Copy(Method.ClassName, 1, Pos('<', Method.ClassName) - 1);
      Method.MethodName := Copy(ANode.Name, Dot + 1, MaxInt);
      Method.Decl := ANode;
      FMethods.Add(Method);
    end;
    // Lokale Routinen gehören nicht zur Klasse.
    Exit;
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    Collect(ANode[Index]);
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

function Prepare(const AContext: TRuleContext; out AModel: TComponentModel): Boolean;
begin
  AModel := nil;
  Result := AContext.Tree <> nil;
  if Result then
    AModel := TComponentModel.Create(AContext);
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
  Info: TClassInfo;
  Method: TMethodImpl;
  Token: TPascalToken;
  Edit: TRuleEdit;
  Inserted: Boolean;
  Confidence: TRuleConfidence;
  Message: string;
begin
  if not Prepare(AContext, Model) then
    Exit;
  try
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
  finally
    Model.Free;
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
  Index: Integer;
  Target: TSyntaxNode;
begin
  if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and SameText(ANode.Name, AField) then
  begin
    Target := ANode[0];
    if (Target.Kind = TSyntaxKind.Identifier) or ((Target.Kind = TSyntaxKind.MemberAccess) and
      (Target.ChildCount = 1) and (Target[0].Kind = TSyntaxKind.Identifier) and SameText(Target[0].Name, 'Self')) then
    begin
      AValue := ANode[1];
      Exit(True);
    end;
  end;
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    Exit(False);
  for Index := 0 to ANode.ChildCount - 1 do
    if FindAssignment(ANode[Index], AField, AValue) then
      Exit(True);
  Result := False;
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
  Info: TClassInfo;
  Prop: TPropertyInfo;
  Ctor: TMethodImpl;
  Value: TSyntaxNode;
  ValueText: string;
  Range: TTextRange;
begin
  if not Prepare(AContext, Model) then
    Exit;
  try
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
  finally
    Model.Free;
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
  Info: TClassInfo;
  Prop: TPropertyInfo;
  Setter, Ctor: TMethodImpl;
  Value: TSyntaxNode;
  Edit: TRuleEdit;
  Parameter: string;
  Range: TTextRange;
begin
  if not Prepare(AContext, Model) then
    Exit;
  try
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
  finally
    Model.Free;
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
  Info: TClassInfo;
  Prop: TPropertyInfo;
  Setter, Paint: TMethodImpl;
  Value: TSyntaxNode;
  Token: TPascalToken;
  Edit: TRuleEdit;
  Message: string;
begin
  if not Prepare(AContext, Model) then
    Exit;
  try
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
  finally
    Model.Free;
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
        if IsIn(Parent.Name, ScaleCalls) or IsIn(Parent.Name, ['RGB', 'TColor', 'Sleep', 'Inc', 'Dec']) then
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
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    Exit;
  if IsPixelLiteral(ANode) and not Excluded(ANode) then
    AList.Add(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    CollectPixels(ANode[Index], AList);
end;

procedure TComponentFixedPixelsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Method: TMethodImpl;
  Literals: TList<TSyntaxNode>;
  Index, Last: Integer;
  Edits: TArray<TRuleEdit>;
  Literal: TSyntaxNode;
begin
  if not Prepare(AContext, Model) then
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
    Model.Free;
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
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    Exit;
  // RGB(…) und TColor(…)
  if (ANode.Kind = TSyntaxKind.Call) and IsIn(ANode.Name, ['RGB', 'TColor']) then
  begin
    AList.Add(ANode);
    Exit;
  end;
  // $00BBGGRR oder eine Zahl, die einer …Color-Eigenschaft zugewiesen wird
  if (ANode.Kind = TSyntaxKind.Literal) and (ANode.Name <> '') and CharInSet(ANode.Name[1], ['$', '0'..'9']) and
    (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and
    EndsText('Color', ANode.Parent.Name) then
    AList.Add(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    CollectColors(ANode[Index], AList);
end;

procedure TComponentHardcodedColorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Method: TMethodImpl;
  Colors: TList<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  if not Prepare(AContext, Model) then
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
    Model.Free;
  end;
end;

procedure RegisterComponentRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TComponentMissingInheritedRule.Create);
  ARegistry.Register(TComponentDefaultMismatchRule.Create);
  ARegistry.Register(TComponentMissingFreeNotificationRule.Create);
  ARegistry.Register(TComponentSetterWithoutInvalidateRule.Create);
  ARegistry.Register(TComponentFixedPixelsRule.Create);
  ARegistry.Register(TComponentHardcodedColorRule.Create);
end;

end.
