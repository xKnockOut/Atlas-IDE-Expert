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
//   inherited-order                      inherited an der falschen Stelle (#1049): im Destruktor vor
//                                        dem Freigeben eigener Felder (nicht bei Threads, deren
//                                        Destroy auf den Thread wartet), im Konstruktor nach einem
//                                        Zugriff auf ein geerbtes Feld bzw. eine geerbte Property
//                                        (über TAncestry.FindMember); Korrektur verschiebt inherited
//   inherited-wrong-method               inherited Laden in der überschriebenen Methode Speichern
//                                        (#1050), meist nach Kopieren; nur Aufrufe (Anweisung oder
//                                        mit Klammern), nicht in Konstruktoren, nicht wenn die Methode
//                                        auch sich selbst geerbt aufruft; Ausnahmen über "allowed"
//   getter-side-effect                   read-Methode einer Property ändert Felder oder Properties des
//                                        Objekts (#1052): Zuweisung, Inc/Dec/Include/Exclude oder ein neu
//                                        angelegtes Objekt an eine Methode eines Felds (FListe.Add(T.Create));
//                                        Lazy-Initialisierung (if prüft, was der Zweig zuweist) ist mit
//                                        "allowLazyInit" (Standard true) erlaubt; geerbte Felder über TAncestry
//   equals-without-gethashcode           Equals ohne GetHashCode überschrieben oder umgekehrt (#1053), still,
//                                        wenn ein Vorfahr das Gegenstück überschreibt oder die Kette unbekannt
//                                        ist; Korrektur GetHashCode über THashBobJenkins mit den Feldern aus
//                                        Equals. Records der Datei mit class operator Equal und Feldern, die der
//                                        Byte-Vergleich falsch vergleicht (string, Variant, Gleitkomma,
//                                        Interface, TArray), als Schlüssel von TDictionary/THashSet ohne Comparer
//
// Die Komponentenregeln prüfen nur Klassen, deren Vorfahrenkette (Datei, Symbolindex) eine
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

  TInheritedOrderRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedWrongMethodRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Erlaubt die Option allowed (Paare "Methode&gt;geerbte Methode", Muster mit * und ?) den Aufruf
    /// inherited AInherited in AMethod?</summary>
    class function Allowed(const APairs: TArray<string>; const AMethod, AInherited: string): Boolean; static;
  end;

  TGetterSideEffectRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TEqualsWithoutGetHashCodeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Hashwert des Felds AField vom Typ ATypeName, verkettet mit AInitial; ACompare ist die Funktion, in
    /// der Equals das Feld vergleicht (SameText: ohne Groß-/Kleinschreibung, also auch der Hashwert).</summary>
    class function HashExpression(const AField, ATypeName, ACompare, AInitial: string): string; static;
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
  Atlas.Common.Editing.UsesClause,
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
  // Konstruktoren der VCL-Vorfahren, die ein Konstruktor ohne inherited aufrufen darf: CreateNew legt ein Formular
  // ohne DFM an und ruft selbst inherited Create (#1109).
  AncestorConstructors: array[0..2] of string = ('CreateNew', 'CreateParented', 'CreateParentedControl');
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

/// <summary>Skaliert der Aufruf seinen Wert? Neben ScaleValue &amp; Co. auch eigene Helfer wie Scale(3) oder
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
    else
      // Übrige Werte bewusst ohne Wirkung.
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

/// <summary>Sind alle Argumente des Aufrufs ACall Zahlenliterale (RGB(255, 0, 0), TColor($00FF00))?</summary>
function LiteralArguments(ACall: TSyntaxNode): Boolean;
var
  Index: Integer;
  Argument: TSyntaxNode;
begin
  Result := ACall.ChildCount > 1;
  for Index := 1 to ACall.ChildCount - 1 do
  begin
    Argument := ACall[Index];
    if (Argument.Kind <> TSyntaxKind.Literal) or (Argument.Name = '') or
      not CharInSet(Argument.Name[1], ['$', '0'..'9']) then
      Exit(False);
  end;
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
      // RGB(…) und TColor(…) mit Zahlen; TColor(FColors.Surface) wandelt eine Farbe des Themas um (#1109).
      if (AVisited.Kind = TSyntaxKind.Call) and IsIn(AVisited.Name, ['RGB', 'TColor']) then
      begin
        if LiteralArguments(AVisited) then
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

  // Ruft der Rumpf einen anderen Konstruktor derselben Klasse auf (Create(nil), Self.Create(nil)) oder CreateNew?
  function CallsOwnConstructor(ARoot: TSyntaxNode): Boolean;
  var
    Node, Target: TSyntaxNode;
    Child: Integer;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
          Continue;
        if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount > 0) then
        begin
          Target := Node[0];
          if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
            Target := Target[0];
          if ((Target.Kind = TSyntaxKind.Identifier) or ((Target.Kind = TSyntaxKind.MemberAccess) and
            (Target.ChildCount = 1) and (Target[0].Kind = TSyntaxKind.Identifier) and
            SameText(Target[0].Name, 'Self'))) and (IsIn(Target.Name, Constructors) or
            IsIn(Target.Name, AncestorConstructors)) then
            Exit(True);
        end;
        for Child := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Child]);
      end;
    finally
      Pending.Free;
    end;
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

{ TInheritedOrderRule }

function TInheritedOrderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-order', TRuleSeverity.Warning, 'inherited an der falschen Stelle');
end;

/// <summary>Ist AStatement ein Aufruf von inherited (inherited; inherited Name; inherited Name(…))?</summary>
function IsInheritedCall(AStatement: TSyntaxNode; out AName: string): Boolean;
var
  Node: TSyntaxNode;
begin
  Result := False;
  AName := '';
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount <> 1) then
    Exit;
  Node := AStatement[0];
  if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) then
    Node := Node[0];
  if Node.Kind <> TSyntaxKind.InheritedExpr then
    Exit;
  AName := Node.Name;
  Result := True;
end;

/// <summary>Namen der Felder der Klasse (auch "FA, FB: T").</summary>
function OwnFields(const AClass: TClassInfo): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to AClass.Body.ChildCount - 1 do
    if AClass.Body[Index].Kind = TSyntaxKind.Field then
      for Name in AClass.Body[Index].Name.Split([',']) do
        if Trim(Name) <> '' then
          Result := Result + [Trim(Name)];
end;

/// <summary>Namen der Felder, Properties und Methoden der Klasse selbst.</summary>
function OwnMembers(const AClass: TClassInfo): TArray<string>;
var
  Index: Integer;
begin
  Result := OwnFields(AClass);
  for Index := 0 to AClass.Body.ChildCount - 1 do
    if AClass.Body[Index].Kind in [TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader] then
      Result := Result + [AClass.Body[Index].Name];
end;

/// <summary>Parameter und lokale Variablen (var-Abschnitte) einer Methode.</summary>
function MethodLocalNames(const AMethod: TMethodImpl): TArray<string>;
var
  Header, Section: TSyntaxNode;
  Index, Inner: Integer;
  Name: string;
begin
  Result := nil;
  Header := AMethod.Decl.FindChild(TSyntaxKind.RoutineHeader);
  if Header <> nil then
  begin
    Section := Header.FindChild(TSyntaxKind.Parameters);
    if Section <> nil then
      for Index := 0 to Section.ChildCount - 1 do
        for Name in Section[Index].Name.Split([',']) do
          Result := Result + [Trim(Name)];
  end;
  for Index := 0 to AMethod.Decl.ChildCount - 1 do
    if AMethod.Decl[Index].Kind = TSyntaxKind.VarSection then
      for Inner := 0 to AMethod.Decl[Index].ChildCount - 1 do
        for Name in AMethod.Decl[Index][Inner].Name.Split([',']) do
          Result := Result + [Trim(Name)];
end;

/// <summary>Bezeichner F bzw. Self.F als Ziel einer Freigabe: F.Free, F.DisposeOf, F.Destroy, FreeAndNil(F).</summary>
function FreedName(ANode: TSyntaxNode): string;
var
  Target: TSyntaxNode;
begin
  Result := '';
  Target := nil;
  if (ANode.Kind = TSyntaxKind.MemberAccess) and IsIn(ANode.Name, ['Free', 'DisposeOf', 'Destroy']) and
    (ANode.ChildCount = 1) then
    Target := ANode[0]
  else if (ANode.Kind = TSyntaxKind.Call) and IsIn(ANode.Name, ['FreeAndNil', 'Dispose', 'FreeMem']) and
    (ANode.ChildCount = 2) then
    Target := ANode[1];
  if Target = nil then
    Exit;
  if (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount = 1) and
    (Target[0].Kind = TSyntaxKind.Identifier) and SameText(Target[0].Name, 'Self') then
    Exit(Target.Name);
  if Target.Kind = TSyntaxKind.Identifier then
    Result := Target.Name;
end;

/// <summary>Erstes freigegebenes eigenes Feld in ANode, '' ohne.</summary>
function FirstFreedField(ANode: TSyntaxNode; const AFields: TArray<string>): string;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Result := FreedName(Node);
      if (Result <> '') and IsIn(Result, AFields) then
        Exit;
      if Node.Kind = TSyntaxKind.AnonymousMethod then
        Continue;
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
    Result := '';
  finally
    Pending.Free;
  end;
end;

procedure TInheritedOrderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Lines: TArray<string>;
  LineBreak: string;

  function FindClassInfo(const AName: string; out AInfo: TClassInfo): Boolean;
  var
    Info: TClassInfo;
  begin
    for Info in Model.Classes do
      if SameText(Info.Name, AName) then
      begin
        AInfo := Info;
        Exit(True);
      end;
    Result := False;
  end;

  // Wartet der Destruktor eines Vorfahren auf etwas (TThread.Destroy beendet und erwartet den Thread)?
  function WaitsInDestructor(const AClassName: string): Boolean;
  var
    Name: string;
    Depth: Integer;
  begin
    Name := AClassName;
    for Depth := 0 to 63 do
    begin
      if ContainsText(Name, 'Thread') then
        Exit(True);
      if (Name = '') or SameText(Name, 'TObject') then
        Break;
      Name := Model.FAncestry.ParentOf(Name);
    end;
    Result := False;
  end;

  // Steht AStatement allein in seinen Zeilen (höchstens mit ";")?
  function OwnLines(AStatement: TSyntaxNode): Boolean;
  begin
    Result := (AStatement.EndPos.Line <= High(Lines)) and
      (Trim(Copy(Lines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character)) = '') and
      IsIn(Trim(Copy(Lines[AStatement.EndPos.Line], AStatement.EndPos.Character + 1, MaxInt)), ['', ';']);
  end;

  // inherited ans Ende bzw. an den Anfang: Zeilen der Anweisung entfernen, Text neu einfügen.
  function MoveFix(ABlock, AStatement: TSyntaxNode; AToEnd: Boolean; out AFix: TRuleFix): Boolean;
  var
    Insert, Remove: TRuleEdit;
    Text: string;
  begin
    Result := False;
    if not OwnLines(AStatement) then
      Exit;
    Text := Model.NodeText(AStatement) + ';';
    if AToEnd then
      Result := Model.InsertBeforeEnd(ABlock, Text, Insert)
    else
      Result := Model.InsertAfterBegin(ABlock, Text, Insert);
    if not Result then
      Exit;
    Remove := TRuleEdit.Create(TTextRange.Create(AStatement.StartPos.Line, 0, AStatement.EndPos.Line + 1, 0), '');
    if AToEnd then
      AFix := TRuleFix.Create('inherited an das Ende des Destruktors verschieben', [Remove, Insert])
    else
      AFix := TRuleFix.Create('inherited an den Anfang des Konstruktors verschieben', [Insert, Remove]);
  end;

  procedure CheckDestructor(const AMethod: TMethodImpl; const AInfo: TClassInfo);
  var
    Index, Later: Integer;
    Statement: TSyntaxNode;
    Name, Field: string;
    Fix: TRuleFix;
  begin
    if WaitsInDestructor(AInfo.Name) then
      Exit;
    for Index := 0 to AMethod.Block.ChildCount - 1 do
    begin
      Statement := AMethod.Block[Index];
      if not IsInheritedCall(Statement, Name) then
        Continue;
      if (Name <> '') and not SameText(Name, AMethod.MethodName) then
        Exit;
      for Later := Index + 1 to AMethod.Block.ChildCount - 1 do
      begin
        Field := FirstFreedField(AMethod.Block[Later], OwnFields(AInfo));
        if Field = '' then
          Continue;
        if MoveFix(AMethod.Block, Statement, True, Fix) then
          AReport.Add(TTextRange.Create(Statement.StartPos, Statement.EndPos),
            Format('inherited vor dem Freigeben der eigenen Felder; der Vorfahr kann noch auf %s zugreifen.',
            [Field]), TRuleConfidence.Medium, [Fix])
        else
          AReport.Add(TTextRange.Create(Statement.StartPos, Statement.EndPos),
            Format('inherited vor dem Freigeben der eigenen Felder; der Vorfahr kann noch auf %s zugreifen.',
            [Field]), TRuleConfidence.Medium);
        Exit;
      end;
      Exit;
    end;
  end;

  // Erstes geerbtes Feld bzw. erste geerbte Property in ANode (F, Self.F); nil ohne.
  function FirstInheritedAccess(ARoot: TSyntaxNode; const AParent: string; const AExcluded: TArray<string>;
    out AName, AOwner: string): TSyntaxNode;
  var
    Index: Integer;
    Name, Unresolved: string;
    Member: TIndexSymbol;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
          Continue;
        Name := '';
        if (Node.Kind = TSyntaxKind.Identifier) and not ((Node.Parent <> nil) and
          (Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] = Node)) then
          Name := Node.Name
        else if (Node.Kind = TSyntaxKind.MemberAccess) and (Node.ChildCount = 1) and
          (Node[0].Kind = TSyntaxKind.Identifier) and SameText(Node[0].Name, 'Self') then
          Name := Node.Name;
        if (Name <> '') and not SameText(Name, 'Self') and not IsIn(Name, AExcluded) and
          Model.FAncestry.FindMember(AParent, Name, Member, Unresolved) and
          (Member.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
        begin
          AName := Name;
          AOwner := Member.Container;
          Exit(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Verwenden die Argumente von inherited Create(…) lokale Variablen, die die Anweisungen davor setzen?
  function ArgumentsUseLocals(ARoot: TSyntaxNode; const ALocals: TArray<string>): Boolean;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Identifier) and IsIn(Node.Name, ALocals) then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CheckConstructor(const AMethod: TMethodImpl; const AInfo: TClassInfo);
  var
    Index, Earlier: Integer;
    Statement, Access: TSyntaxNode;
    Name, Member, Owner, Parent: string;
    Locals, Excluded: TArray<string>;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    Parent := DeclaredParent(AInfo);
    if (Parent = '') or SameText(Parent, 'TObject') or Model.HasToken(AMethod.Block, ['with']) then
      Exit;
    Locals := MethodLocalNames(AMethod);
    Excluded := Locals + OwnMembers(AInfo);
    for Index := 0 to AMethod.Block.ChildCount - 1 do
    begin
      Statement := AMethod.Block[Index];
      if not IsInheritedCall(Statement, Name) then
        Continue;
      for Earlier := 0 to Index - 1 do
      begin
        Access := FirstInheritedAccess(AMethod.Block[Earlier], Parent, Excluded, Member, Owner);
        if Access = nil then
          Continue;
        Fixes := nil;
        if not ArgumentsUseLocals(Statement, Locals) and MoveFix(AMethod.Block, Statement, False, Fix) then
          Fixes := [Fix];
        AReport.Add(TTextRange.Create(Access.StartPos, Access.EndPos),
          Format('%s greift vor inherited auf %s aus %s zu; der Vorfahr ist noch nicht angelegt.',
          [AMethod.MethodName, Member, Owner]), TRuleConfidence.Medium, Fixes);
        Exit;
      end;
      Exit;
    end;
  end;

var
  Method: TMethodImpl;
  Info: TClassInfo;
  Source: string;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) or not ContainsText(AContext.Text, 'inherited') then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  for Method in Model.Methods do
  begin
    if not FindClassInfo(Method.ClassName, Info) then
      Continue;
    Source := TrimLeft(Model.NodeText(Method.Decl));
    if StartsText('destructor', Source) then
      CheckDestructor(Method, Info)
    else if StartsText('constructor', Source) then
      CheckConstructor(Method, Info);
  end;
end;

{ TInheritedWrongMethodRule }

function TInheritedWrongMethodRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-wrong-method', TRuleSeverity.Warning,
    'inherited ruft eine andere Methode');
end;

class function TInheritedWrongMethodRule.Allowed(const APairs: TArray<string>;
  const AMethod, AInherited: string): Boolean;
var
  Pair: string;
  Separator: Integer;
begin
  for Pair in APairs do
  begin
    Separator := Pos('>', Pair);
    if (Separator > 0) and MatchesGlob(Trim(Copy(Pair, 1, Separator - 1)), AMethod) and
      MatchesGlob(Trim(Copy(Pair, Separator + 1, MaxInt)), AInherited) then
      Exit(True);
  end;
  Result := False;
end;

procedure TInheritedWrongMethodRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Pairs: TArray<string>;

  function FindClassInfo(const AName: string; out AInfo: TClassInfo): Boolean;
  var
    Info: TClassInfo;
  begin
    for Info in Model.Classes do
      if SameText(Info.Name, AName) then
      begin
        AInfo := Info;
        Exit(True);
      end;
    Result := False;
  end;

  // Aufrufe inherited Name bzw. inherited Name(…) als Anweisung oder mit Klammern; nur sie sind sicher Methoden
  // (inherited Caption ohne Klammern kann eine Property sein).
  procedure CollectCalls(ARoot: TSyntaxNode; var ACalls: TArray<TSyntaxNode>; var ASameName: Boolean;
    const AMethodName: string);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.InheritedExpr then
        begin
          if (Node.Name = '') or SameText(Node.Name, AMethodName) then
            ASameName := True
          else if (Node.Parent <> nil) and ((Node.Parent.Kind = TSyntaxKind.CallStatement) or
            ((Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] = Node))) then
            ACalls := ACalls + [Node];
        end;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
          Continue;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Anzahl der Parameter im Kopf der Methode (A, B: Integer zählt zwei).
  function ParameterCount(const AMethod: TMethodImpl): Integer;
  var
    Header, Section: TSyntaxNode;
    Index: Integer;
  begin
    Result := 0;
    Header := AMethod.Decl.FindChild(TSyntaxKind.RoutineHeader);
    if Header = nil then
      Exit;
    Section := Header.FindChild(TSyntaxKind.Parameters);
    if Section <> nil then
      for Index := 0 to Section.ChildCount - 1 do
        Inc(Result, Length(Section[Index].Name.Split([','])));
  end;

var
  Method: TMethodImpl;
  Info: TClassInfo;
  Calls: TArray<TSyntaxNode>;
  Call: TSyntaxNode;
  SameName: Boolean;
  Arguments: Integer;
  Source, Message: string;
  Fixes: TArray<TRuleFix>;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) or not ContainsText(AContext.Text, 'inherited') then
    Exit;
  Pairs := TRuleOptions.Strings(AContext.Options, 'allowed', nil);
  for Method in Model.Methods do
  begin
    // Konstruktoren dürfen jeden geerbten Konstruktor aufrufen (inherited Create(nil)).
    Source := TrimLeft(Model.NodeText(Method.Decl));
    if StartsText('constructor', Source) or StartsText('class ', Source) or
      not FindClassInfo(Method.ClassName, Info) or not Model.DeclaredWith(Info, Method.MethodName, 'override') then
      Continue;
    Calls := nil;
    SameName := False;
    CollectCalls(Method.Block, Calls, SameName, Method.MethodName);
    // Ruft die Methode auch sich selbst im Vorfahren auf, ist der andere Aufruf gewollt.
    if SameName then
      Continue;
    for Call in Calls do
    begin
      if Allowed(Pairs, Method.MethodName, Call.Name) then
        Continue;
      Message := Format('%s ruft inherited %s auf; gemeint ist vermutlich inherited %s.',
        [Method.MethodName, Call.Name, Method.MethodName]);
      Fixes := nil;
      // Mit gleicher Zahl an Argumenten wie Parametern passt der eigene Name.
      Arguments := 0;
      if Call.Parent.Kind = TSyntaxKind.Call then
        Arguments := Call.Parent.ChildCount - 1;
      if Arguments = ParameterCount(Method) then
        Fixes := [TRuleFix.Create(Format('inherited %s aufrufen', [Method.MethodName]),
          [TRuleEdit.Create(TTextRange.Create(Call.StartPos, Call.EndPos), 'inherited ' + Method.MethodName)])];
      AReport.Add(TTextRange.Create(Call.StartPos, Call.EndPos), Message, TRuleConfidence.High, Fixes);
    end;
  end;
end;

{ TGetterSideEffectRule }

function TGetterSideEffectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('getter-side-effect', TRuleSeverity.Warning, 'Getter verändert den Zustand');
end;

/// <summary>F bzw. Self.F als Ziel; '' sonst.</summary>
function SelfMemberName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := ANode.Name
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
    Result := ANode.Name;
end;

/// <summary>Namen (F, Self.F, Result, lokale Variablen), denen unter ANode zugewiesen wird.</summary>
procedure CollectAssignedNames(ANode: TSyntaxNode; var ANames: TArray<string>);
var
  Index: Integer;
  Name: string;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount > 0) then
      begin
        Name := SelfMemberName(Node[0]);
        if Name <> '' then
          ANames := ANames + [Name];
      end;
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Nennt ANode einen der Namen (F oder Self.F)?</summary>
function MentionsName(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
var
  Index: Integer;
  Name: string;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Name := SelfMemberName(Node);
      if (Name <> '') and IsIn(Name, ANames) then
        Exit(True);
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Enthält ANode einen Konstruktoraufruf (X.Create, X.Create(…))?</summary>
function ContainsCreate(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', Node.Name) then
        Exit(True);
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Lazy-Initialisierung: Ein umschließendes if (bis ARoot) prüft in der Bedingung etwas, das im Zweig
/// mit ANode zugewiesen wird (if FListe = nil then FListe := …, if Result = nil then … FX := Result).</summary>
function IsLazyInit(ANode, ARoot: TSyntaxNode): Boolean;
var
  Branch, Condition: TSyntaxNode;
  AssignedNames: TArray<string>;
begin
  Branch := ANode;
  while (Branch <> nil) and (Branch <> ARoot) and (Branch.Parent <> nil) do
  begin
    Condition := nil;
    if (Branch.Parent.Kind = TSyntaxKind.IfStatement) and (Branch.Parent.ChildCount > 1) and
      (Branch.Parent[0] <> Branch) then
      Condition := Branch.Parent[0];
    if Condition <> nil then
    begin
      AssignedNames := nil;
      CollectAssignedNames(Branch, AssignedNames);
      if MentionsName(Condition, AssignedNames) then
        Exit(True);
    end;
    Branch := Branch.Parent;
  end;
  Result := False;
end;

procedure TGetterSideEffectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  AllowLazyInit: Boolean;
  Info: TClassInfo;
  Parent: string;
  Members, Locals, Reported: TArray<string>;

  // Feld oder Property des Objekts: eigene aus der Klasse, geerbte über TAncestry.
  function IsState(const AName: string): Boolean;
  var
    Member: TIndexSymbol;
    Unresolved: string;
  begin
    if (AName = '') or SameText(AName, 'Result') or SameText(AName, 'Self') or IsIn(AName, Locals) then
      Exit(False);
    if IsIn(AName, Members) then
      Exit(True);
    Result := (Parent <> '') and Model.FAncestry.FindMember(Parent, AName, Member, Unresolved) and
      (Member.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]);
  end;

  // Geändertes Mitglied an ANode: Ziel einer Zuweisung, Inc/Dec/Include/Exclude, Methode eines Felds mit neu
  // angelegtem Objekt als Argument (FListe.Add(TEintrag.Create)); nil ohne.
  function ChangedTarget(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := nil;
    if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount > 0) then
      Result := ANode[0]
    else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and IsIn(ANode[0].Name, ['Inc', 'Dec', 'Include', 'Exclude']) then
      Result := ANode[1]
    else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and (ANode[0].ChildCount = 1) then
      for Index := 1 to ANode.ChildCount - 1 do
        if ContainsCreate(ANode[Index]) then
          Exit(ANode[0][0]);
  end;

  procedure Visit(ANode, ARoot: TSyntaxNode; const AGetter: string);
  var
    Node, Target: TSyntaxNode;
    Name: string;
    Index: Integer;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
          Continue;
        Target := ChangedTarget(Node);
        if Target <> nil then
        begin
          Name := SelfMemberName(Target);
          if IsState(Name) and not IsIn(Name, Reported) and not (AllowLazyInit and IsLazyInit(Node, ARoot)) then
          begin
            Reported := Reported + [Name];
            AReport.Add(TTextRange.Create(Target.StartPos, Target.EndPos),
              Format('Der Getter %s verändert %s; schon das Anzeigen im Debugger ändert den Zustand.', [AGetter, Name]),
              TRuleConfidence.Medium);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Prop: TPropertyInfo;
  Method: TMethodImpl;
  Getters: TArray<string>;
  Index: Integer;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) then
    Exit;
  AllowLazyInit := TRuleOptions.Bool(AContext.Options, 'allowLazyInit', True);
  for Info in Model.Classes do
  begin
    Getters := nil;
    for Prop in Model.Properties(Info) do
      if (Prop.ReadName <> '') and not IsIn(Prop.ReadName, Getters) then
        Getters := Getters + [Prop.ReadName];
    if Getters = nil then
      Continue;
    Parent := DeclaredParent(Info);
    Members := OwnFields(Info);
    for Index := 0 to Info.Body.ChildCount - 1 do
      if Info.Body[Index].Kind = TSyntaxKind.PropertyDecl then
        Members := Members + [Info.Body[Index].Name];
    for Method in Model.Methods do
      if SameText(Method.ClassName, Info.Name) and IsIn(Method.MethodName, Getters) and
        not Model.HasToken(Method.Block, ['with']) then
      begin
        Locals := MethodLocalNames(Method);
        Reported := nil;
        Visit(Method.Block, Method.Block, Method.MethodName);
      end;
  end;
end;

{ TEqualsWithoutGetHashCodeRule }

const
  // Feldtypen, bei denen der Standard-Comparer für Records (Byte für Byte) nicht zu Equal passt.
  BinaryUnsafeTypes: array[0..12] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString',
    'RawByteString', 'UTF8String', 'ShortString', 'Variant', 'OleVariant', 'Double', 'Single', 'Extended', 'Real');
  // Generische Sammlungen, deren erster Typparameter der Schlüssel ist.
  HashedCollections: array[0..3] of string = ('TDictionary', 'TObjectDictionary', 'THashSet', 'TMultiMap');

function TEqualsWithoutGetHashCodeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('equals-without-gethashcode', TRuleSeverity.Warning,
    'Equals ohne GetHashCode');
end;

/// <summary>Kopf AName im Klassen- bzw. Record-Rumpf ABody; nil ohne.</summary>
function MemberHeader(ABody: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ABody.ChildCount - 1 do
    if (ABody[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(ABody[Index].Name, AName) then
      Exit(ABody[Index]);
  Result := nil;
end;

/// <summary>Typ des Felds AName im Rumpf ABody (Field "A,B" mit TypeReference); '' ohne.</summary>
function FieldTypeName(ABody: TSyntaxNode; const AName: string): string;
var
  Index: Integer;
  Name: string;
  TypeRef: TSyntaxNode;
begin
  for Index := 0 to ABody.ChildCount - 1 do
    if ABody[Index].Kind = TSyntaxKind.Field then
      for Name in ABody[Index].Name.Split([',']) do
        if SameText(Trim(Name), AName) then
        begin
          TypeRef := ABody[Index].FindChild(TSyntaxKind.TypeReference);
          if TypeRef = nil then
            Exit('');
          Exit(TypeRef.Name);
        end;
  Result := '';
end;

class function TEqualsWithoutGetHashCodeRule.HashExpression(const AField, ATypeName, ACompare,
  AInitial: string): string;
var
  Value: string;
begin
  if MatchText(ATypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String']) then
  begin
    // Vergleicht Equals ohne Groß-/Kleinschreibung, muss der Hashwert es ebenso tun.
    Value := AField;
    if MatchText(ACompare, ['SameText', 'CompareText']) then
      Value := 'LowerCase(' + AField + ')'
    else if MatchText(ACompare, ['AnsiSameText', 'AnsiCompareText']) then
      Value := 'AnsiLowerCase(' + AField + ')';
    Result := Format('THashBobJenkins.GetHashValue(%s, %s)', [Value, AInitial]);
  end
  else
    Result := Format('THashBobJenkins.GetHashValue(%s, SizeOf(%s), %s)', [AField, AField, AInitial]);
end;

procedure TEqualsWithoutGetHashCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;

  // Überschreibt ein Vorfahr (ohne TObject) die Methode AName? AKnown: die Kette ist bekannt.
  function AncestorOverrides(const AClass, AName: string; out AKnown: Boolean): Boolean;
  var
    Chain: TArray<TSymbolLocation>;
    Location: TSymbolLocation;
    Member: TIndexSymbol;
    ObjectMissing: Boolean;
  begin
    Result := False;
    Chain := Model.FAncestry.Ancestors(AClass, AKnown, ObjectMissing);
    for Location in Chain do
      if not SameText(Location.Symbol.Name, 'TObject') then
        for Member in Model.FAncestry.Methods(Location) do
          if SameText(Member.Name, AName) and Member.HasDirective('override') then
            Exit(True);
  end;

  // Eigene Felder in der Reihenfolge, in der Equals sie nennt, je mit dem Vergleich (SameText …), in dem sie stehen.
  procedure CollectFields(ARoot: TSyntaxNode; const AFields: TArray<string>; var ANames, ACompares: TArray<string>);
  var
    Index: Integer;
    Compare: string;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1); Vorordnung, damit die Reihenfolge der Felder bleibt.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and IsIn(Node.Name, AFields) and
          not IsIn(Node.Name, ANames) then
        begin
          Compare := '';
          if (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] <> Node) then
            Compare := Node.Parent.Name;
          ANames := ANames + [Node.Name];
          ACompares := ACompares + [Compare];
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Korrektur: GetHashCode hinter Equals deklarieren und hinter dem Rumpf von Equals umsetzen.
  function HashFix(const AInfo: TClassInfo; AHeader: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    Method, Equals_: TMethodImpl;
    Found: Boolean;
    Names, Compares: TArray<string>;
    Index: Integer;
    Body, Initial: string;
    Edit, UsesEdit: TRuleEdit;
    Edits: TArray<TRuleEdit>;
    Position: TTextPosition;
  begin
    Result := False;
    Found := False;
    for Method in Model.Methods do
      if SameText(Method.ClassName, AInfo.Name) and SameText(Method.MethodName, 'Equals') then
      begin
        Equals_ := Method;
        Found := True;
      end;
    if not Found then
      Exit;
    Names := nil;
    Compares := nil;
    CollectFields(Equals_.Block, OwnFields(AInfo), Names, Compares);
    if Names = nil then
      Exit;
    Body := '';
    Initial := '0';
    for Index := 0 to High(Names) do
    begin
      Body := Body + '  Result := ' + HashExpression(Names[Index], FieldTypeName(AInfo.Body, Names[Index]),
        Compares[Index], Initial) + ';' + Model.FLineBreak;
      Initial := 'Result';
    end;
    // Edits in Textreihenfolge: Deklaration, uses der Implementierung, Rumpf.
    Position := TTextPosition.Create(AHeader.EndPos.Line + 1, 0);
    Edits := [TRuleEdit.Create(TTextRange.Create(Position, Position), StringOfChar(' ', AHeader.StartPos.Character) +
      'function GetHashCode: Integer; override;' + Model.FLineBreak)];
    if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(AContext.Tree.Tokens), 'System.Hash', AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, Equals_.Decl.StartOffset, 'System.Hash', Model.FLineBreak,
      UsesEdit) then
    begin
      if UsesEdit.Range.StartPos.Line < AHeader.StartPos.Line then
        Edits := [UsesEdit] + Edits
      else
        Edits := Edits + [UsesEdit];
    end;
    Position := TTextPosition.Create(Equals_.Decl.EndPos.Line + 1, 0);
    Edit := TRuleEdit.Create(TTextRange.Create(Position, Position), Model.FLineBreak + 'function ' + AInfo.Name +
      '.GetHashCode: Integer;' + Model.FLineBreak + 'begin' + Model.FLineBreak + Body + 'end;' + Model.FLineBreak);
    Edits := Edits + [Edit];
    AFix := TRuleFix.Create(Format('GetHashCode mit %s überschreiben (THashBobJenkins)',
      [string.Join(', ', Names)]), Edits);
    Result := True;
  end;

  procedure CheckClasses;
  var
    Info: TClassInfo;
    Header: TSyntaxNode;
    HasEquals, HasHash, Known: Boolean;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    for Info in Model.Classes do
    begin
      HasEquals := Model.DeclaredWith(Info, 'Equals', 'override');
      HasHash := Model.DeclaredWith(Info, 'GetHashCode', 'override');
      if HasEquals = HasHash then
        Continue;
      if HasEquals then
      begin
        if AncestorOverrides(Info.Name, 'GetHashCode', Known) or not Known then
          Continue;
        Header := MemberHeader(Info.Body, 'Equals');
        Fixes := nil;
        if HashFix(Info, Header, Fix) then
          Fixes := [Fix];
        AReport.Add(TTextRange.Create(Header.StartPos, Header.EndPos), 'Equals ist überschrieben, GetHashCode ' +
          'nicht; als Schlüssel in TDictionary finden sich gleiche Objekte nicht.', TRuleConfidence.High, Fixes);
      end
      else
      begin
        if AncestorOverrides(Info.Name, 'Equals', Known) or not Known then
          Continue;
        Header := MemberHeader(Info.Body, 'GetHashCode');
        AReport.Add(TTextRange.Create(Header.StartPos, Header.EndPos), 'GetHashCode ist überschrieben, Equals ' +
          'nicht; als Schlüssel in TDictionary gelten gleiche Objekte weiter als verschieden.', TRuleConfidence.High);
      end;
    end;
  end;

  // Records der Datei mit class operator Equal und einem Feld, das der Byte-Vergleich falsch vergleicht.
  procedure CollectRecords(ARoot: TSyntaxNode; var ANames: TArray<string>);
  var
    Index: Integer;
    Node, Body, Header: TSyntaxNode;
    TypeName: string;
    Unsafe: Boolean;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.TypeDecl then
        begin
          Body := Node.FindChild(TSyntaxKind.RecordType);
          if Body <> nil then
          begin
            Header := MemberHeader(Body, 'Equal');
            Unsafe := False;
            for Index := 0 to Body.ChildCount - 1 do
              if Body[Index].Kind = TSyntaxKind.Field then
              begin
                TypeName := FieldTypeName(Body, Trim(Body[Index].Name.Split([','])[0]));
                if MatchText(TypeName, BinaryUnsafeTypes) or SameText(TypeName, 'TArray') or
                  ((Length(TypeName) > 1) and (TypeName[1] = 'I') and CharInSet(TypeName[2], ['A'..'Z'])) then
                  Unsafe := True;
              end;
            if (Header <> nil) and ContainsText(Model.NodeText(Header), 'operator') and Unsafe then
              ANames := ANames + [Node.Name];
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Argumente ohne möglichen Comparer: nur Literale und Mengen (Kapazität, Besitz).
  function OnlyConstants(ACall: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    for Index := 1 to ACall.ChildCount - 1 do
      if not (ACall[Index].Kind in [TSyntaxKind.Literal, TSyntaxKind.SetConstructor]) then
        Exit(False);
    Result := True;
  end;

  procedure CheckCreates(ARoot: TSyntaxNode; const ARecords: TArray<string>);
  var
    Index: Integer;
    Node, Collection, Args: TSyntaxNode;
    Key: string;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.MemberAccess) and SameText(Node.Name, 'Create') and (Node.ChildCount = 1) and
          (Node[0].Kind = TSyntaxKind.MemberAccess) and IsIn(Node[0].Name, HashedCollections) then
        begin
          Collection := Node[0];
          Args := Collection.FindChild(TSyntaxKind.GenericArgs);
          Key := '';
          if (Args <> nil) and (Args.ChildCount > 0) then
            Key := Args[0].Name;
          if (Key <> '') and IsIn(Key, ARecords) and (not ((Node.Parent <> nil) and
            (Node.Parent.Kind = TSyntaxKind.Call) and (Node.Parent[0] = Node)) or OnlyConstants(Node.Parent)) then
            AReport.Add(TTextRange.Create(Collection.StartPos, Collection.EndPos), Format('%s hat class operator ' +
              'Equal, %s vergleicht Schlüssel ohne Comparer aber Byte für Byte; gleiche Schlüssel finden sich nicht.',
              [Key, Collection.Name]), TRuleConfidence.High);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Records: TArray<string>;
begin
  Cache := TRuleDerived.Open(AContext);
  if not Prepare(Cache, AContext, Model) then
    Exit;
  if ContainsText(AContext.Text, 'Equals') or ContainsText(AContext.Text, 'GetHashCode') then
    CheckClasses;
  if ContainsText(AContext.Text, 'operator') then
  begin
    Records := nil;
    CollectRecords(AContext.Tree.Root, Records);
    if Records <> nil then
      CheckCreates(AContext.Tree.Root, Records);
  end;
end;

procedure RegisterComponentRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMissingInheritedRule.Create);
  ARegistry.Register(TMessageHandlerWithoutInheritedRule.Create);
  ARegistry.Register(TInheritedOrderRule.Create);
  ARegistry.Register(TInheritedWrongMethodRule.Create);
  ARegistry.Register(TGetterSideEffectRule.Create);
  ARegistry.Register(TEqualsWithoutGetHashCodeRule.Create);
  ARegistry.Register(TComponentMissingInheritedRule.Create);
  ARegistry.Register(TComponentDefaultMismatchRule.Create);
  ARegistry.Register(TComponentMissingFreeNotificationRule.Create);
  ARegistry.Register(TComponentSetterWithoutInvalidateRule.Create);
  ARegistry.Register(TComponentFixedPixelsRule.Create);
  ARegistry.Register(TComponentHardcodedColorRule.Create);
end;

end.
