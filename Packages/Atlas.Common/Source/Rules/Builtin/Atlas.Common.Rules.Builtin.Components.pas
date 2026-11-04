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
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Components.Model,
  Atlas.Common.Rules.Builtin.Components.InheritedCalls,
  Atlas.Common.Rules.Builtin.Components.Members;

{ TComponentMissingInheritedRule }

function TComponentMissingInheritedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-missing-inherited', TRuleSeverity.Warning,
    'Überschriebene Komponentenmethode ruft inherited nicht auf');
end;

/// <summary>Überschreibt AMethod von AClass eine Methode aus InheritedMethods ohne inherited? AToken: Name im
/// Kopf der Implementierung.</summary>
function LacksInherited(AModel: TComponentModel; const AClass: TClassInfo; const AMethod: TMethodImpl;
  out AToken: TPascalToken): Boolean;
begin
  Result := SameText(AMethod.ClassName, AClass.Name) and IsIn(AMethod.MethodName, InheritedMethods) and
    AModel.DeclaredWith(AClass, AMethod.MethodName, 'override') and not AModel.HasToken(AMethod.Block,
    ['inherited']);
  Result := Result and AModel.NameToken(AMethod, AToken);
end;

/// <summary>Meldung zu AMethod ohne inherited; False, wenn sie still bleibt. TCustomControl.Paint und
/// TGraphicControl.Paint sind leer: Paint nur melden, wenn ein Vorfahr selbst zeichnet. Die übrigen Methoden tun
/// in jedem VCL-Vorfahren eigene Arbeit.</summary>
function MissingInheritedMessage(AModel: TComponentModel; const AClassName, AMethodName: string;
  out AMessage: string; out AConfidence: TRuleConfidence): Boolean;
var
  mAncestor: string;
  mOnPaintOnly: Boolean;
begin
  AConfidence := TRuleConfidence.High;
  AMessage := Format('%s.%s ruft inherited nicht auf; die VCL erledigt dort eigene Arbeit',
    [AClassName, AMethodName]);
  Result := not SameText(AMethodName, 'Paint');
  if Result or not AModel.PaintingAncestor(AClassName, mAncestor, mOnPaintOnly) then
  begin
    Exit;
  end;
  AConfidence := TRuleConfidence.Medium;
  if not mOnPaintOnly then
  begin
    AMessage := Format('%s.Paint ruft inherited nicht auf; %s.Paint zeichnet dort selbst', [AClassName, mAncestor]);
  end
  else
  begin
    AMessage := Format('%s.Paint ruft inherited nicht auf; %s.Paint löst dort OnPaint aus', [AClassName, mAncestor]);
  end;
  Result := not mOnPaintOnly or AModel.MayUseOnPaint;
end;

/// <summary>Meldung am Namen AToken mit Korrektur "inherited;": im Destruktor zuletzt, sonst zuerst.</summary>
procedure ReportMissingInherited(AModel: TComponentModel; const AMethod: TMethodImpl; const AToken: TPascalToken;
  const AMessage: string; AConfidence: TRuleConfidence; const AReport: IRuleReport);
var
  mEdit: TRuleEdit;
  mInserted: Boolean;
begin
  if SameText(AMethod.MethodName, 'Destroy') then
  begin
    mInserted := AModel.InsertBeforeEnd(AMethod.Block, 'inherited;', mEdit);
  end
  else
  begin
    mInserted := AModel.InsertAfterBegin(AMethod.Block, 'inherited;', mEdit);
  end;
  if mInserted then
  begin
    AReport.Add(TTextRange.Create(AToken.StartPos, AToken.EndPos), AMessage, AConfidence,
      [TRuleFix.Create('"inherited;" einfügen', [mEdit])]);
  end
  else
  begin
    AReport.Add(TTextRange.Create(AToken.StartPos, AToken.EndPos), AMessage, AConfidence);
  end;
end;

procedure TComponentMissingInheritedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mInfo: TClassInfo;
  mMethod: TMethodImpl;
  mToken: TPascalToken;
  mConfidence: TRuleConfidence;
  mMessage: string;
begin
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  for mInfo in mModel.Classes do
  begin
    if not mModel.IsComponent(mInfo.Name) then
    begin
      Continue;
    end;
    for mMethod in mModel.Methods do
    begin
      if LacksInherited(mModel, mInfo, mMethod, mToken) and MissingInheritedMessage(mModel, mInfo.Name,
        mMethod.MethodName, mMessage, mConfidence) then
      begin
        ReportMissingInherited(mModel, mMethod, mToken, mMessage, mConfidence, AReport);
      end;
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
        begin
          Exit(TSyntaxSearchStep.Found);
        end;
      end;
      if AVisited.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
  Result := Found <> nil;
  if Result then
  begin
    AValue := Found[1];
  end;
end;

/// <summary>Gleicher Wert? Zahlen werden verglichen ($-Hex wie dezimal), sonst der Text.</summary>
function SameValue(const A, B: string): Boolean;
var
  NumberA, NumberB: Int64;
begin
  if TryStrToInt64(A, NumberA) and TryStrToInt64(B, NumberB) then
  begin
    Result := NumberA = NumberB;
  end
  else
  begin
    Result := SameText(StringReplace(A, ' ', '', [rfReplaceAll]), StringReplace(B, ' ', '', [rfReplaceAll]));
  end;
end;

/// <summary>Setzt der Konstruktor ACtor das Feld hinter AProp auf einen festen Wert, der nicht default
/// entspricht? AValueText: der Wert im Konstruktor.</summary>
function MismatchedDefault(AModel: TComponentModel; const ACtor: TMethodImpl; const AProp: TPropertyInfo;
  out AValueText: string): Boolean;
var
  mValue: TSyntaxNode;
begin
  AValueText := '';
  Result := AProp.HasDefault and (AProp.ReadName <> '') and FindAssignment(ACtor.Block, AProp.ReadName, mValue);
  // Nur feste Werte geben eine Aussage.
  Result := Result and (mValue.Kind in [TSyntaxKind.Literal, TSyntaxKind.Identifier, TSyntaxKind.UnaryExpr]);
  if Result then
  begin
    AValueText := AModel.NodeText(mValue);
    Result := not SameValue(AValueText, AProp.DefaultText);
  end;
end;

procedure TComponentDefaultMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mInfo: TClassInfo;
  mProp: TPropertyInfo;
  mCtor: TMethodImpl;
  mValueText: string;
  mRange: TTextRange;
begin
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  for mInfo in mModel.Classes do
  begin
    if not mModel.IsComponent(mInfo.Name) or not mModel.FindMethod(mInfo.Name, 'Create', mCtor) then
    begin
      Continue;
    end;
    for mProp in mModel.Properties(mInfo) do
    begin
      if not MismatchedDefault(mModel, mCtor, mProp, mValueText) then
      begin
        Continue;
      end;
      mRange := TTextRange.Create(mProp.DefaultFirst.StartPos, mProp.DefaultLast.EndPos);
      AReport.Add(mRange, Format('"%s" hat default %s, der Konstruktor setzt %s aber auf %s; der Wert wird ' +
        'dann nicht in der DFM gespeichert oder falsch geladen', [mProp.Name, mProp.DefaultText, mProp.ReadName,
        mValueText]), TRuleConfidence.High,
        [TRuleFix.Create(Format('default auf %s ändern', [mValueText]), [TRuleEdit.Create(mRange, mValueText)])]);
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
  begin
    Exit;
  end;
  Params := Header.FindChild(TSyntaxKind.Parameters);
  if (Params <> nil) and (Params.ChildCount > 0) then
  begin
    Result := Params[Params.ChildCount - 1].Name;
  end;
end;

/// <summary>Eigenschaft vom Typ einer Komponente mit write und Namen im Quelltext.</summary>
function IsComponentReference(AModel: TComponentModel; const AProp: TPropertyInfo): Boolean;
begin
  Result := (AProp.TypeName <> '') and (AProp.WriteName <> '') and (AProp.NameToken.Text <> '') and
    AModel.IsComponent(AProp.TypeName);
end;

/// <summary>Eigene Unterkomponente (im Konstruktor erzeugt): braucht keine Benachrichtigung.</summary>
function OwnSubcomponent(AModel: TComponentModel; const AClassName: string; const AProp: TPropertyInfo): Boolean;
var
  mCtor: TMethodImpl;
  mValue: TSyntaxNode;
begin
  Result := (AProp.ReadName <> '') and AModel.FindMethod(AClassName, 'Create', mCtor) and
    FindAssignment(mCtor.Block, AProp.ReadName, mValue) and ContainsText(AModel.NodeText(mValue), '.Create');
end;

/// <summary>Meldet AProp, wenn ihr Setter kein FreeNotification aufruft; mit Korrektur im Setter.</summary>
procedure CheckFreeNotification(AModel: TComponentModel; const AClassName: string; const AProp: TPropertyInfo;
  const AReport: IRuleReport);
const
  cMessage = '"%s" verweist auf eine fremde Komponente ohne FreeNotification; wird sie freigegeben, ' +
    'bleibt ein ungültiger Zeiger zurück';
var
  mSetter: TMethodImpl;
  mEdit: TRuleEdit;
  mParameter: string;
  mRange: TTextRange;
begin
  mRange := TTextRange.Create(AProp.NameToken.StartPos, AProp.NameToken.EndPos);
  if not AModel.FindMethod(AClassName, AProp.WriteName, mSetter) then
  begin
    // write auf ein Feld: es gibt keinen Setter, in dem FreeNotification stehen könnte.
    if SameText(AProp.WriteName, AProp.ReadName) then
    begin
      AReport.Add(mRange, Format(cMessage, [AProp.Name]), TRuleConfidence.Medium);
    end;
    Exit;
  end;
  if AModel.HasToken(mSetter.Block, ['FreeNotification']) then
  begin
    Exit;
  end;
  mParameter := LastParameter(mSetter);
  if (mParameter <> '') and AModel.InsertBeforeEnd(mSetter.Block, Format('if %s <> nil then', [mParameter]) + ' ' +
    Format('%s.FreeNotification(Self);', [mParameter]), mEdit) then
  begin
    AReport.Add(mRange, Format(cMessage, [AProp.Name]), TRuleConfidence.Medium,
      [TRuleFix.Create('FreeNotification im Setter ergänzen', [mEdit])]);
  end
  else
  begin
    AReport.Add(mRange, Format(cMessage, [AProp.Name]), TRuleConfidence.Medium);
  end;
end;

procedure TComponentMissingFreeNotificationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mInfo: TClassInfo;
  mProp: TPropertyInfo;
begin
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  for mInfo in mModel.Classes do
  begin
    if not mModel.IsComponent(mInfo.Name) then
    begin
      Continue;
    end;
    for mProp in mModel.Properties(mInfo) do
    begin
      if IsComponentReference(mModel, mProp) and not OwnSubcomponent(mModel, mInfo.Name, mProp) then
      begin
        CheckFreeNotification(mModel, mInfo.Name, mProp, AReport);
      end;
    end;
  end;
end;

{ TComponentSetterWithoutInvalidateRule }

function TComponentSetterWithoutInvalidateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-setter-without-invalidate', TRuleSeverity.Hint,
    'Setter ändert ein in Paint gelesenes Feld ohne Invalidate');
end;

/// <summary>Setzt der Setter von AProp das Feld, das Paint liest, ohne neu zu zeichnen? ASetter: der Setter.</summary>
function SetterMissesRepaint(AModel: TComponentModel; const AInfo: TClassInfo; const AProp: TPropertyInfo;
  const APaint: TMethodImpl; out ASetter: TMethodImpl): Boolean;
var
  mValue: TSyntaxNode;
begin
  Result := (AProp.ReadName <> '') and AModel.FindMethod(AInfo.Name, AProp.WriteName, ASetter) and
    FindAssignment(ASetter.Block, AProp.ReadName, mValue) and
    AModel.HasToken(APaint.Block, [AProp.ReadName, AProp.Name]) and not AModel.HasToken(ASetter.Block, RepaintCalls);
end;

procedure TComponentSetterWithoutInvalidateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TComponentModel;
  Cache: IRuleDerivedCache;
  Info: TClassInfo;
  Prop: TPropertyInfo;
  Setter, Paint: TMethodImpl;
  Token: TPascalToken;
  Edit: TRuleEdit;
  Message: string;
begin
  Cache := TRuleDerived.Open(AContext);
  if not PrepareModel(Cache, AContext, Model) then
  begin
    Exit;
  end;
  for Info in Model.Classes do
  begin
    if not Model.IsComponent(Info.Name) or not Model.FindMethod(Info.Name, 'Paint', Paint) then
    begin
      Continue;
    end;
    for Prop in Model.Properties(Info) do
    begin
      if not SetterMissesRepaint(Model, Info, Prop, Paint, Setter) or not Model.NameToken(Setter, Token) then
      begin
        Continue;
      end;
      Message := Format('%s ändert %s, das Paint liest, ohne Invalidate; die Anzeige bleibt veraltet',
        [Setter.MethodName, Prop.ReadName]);
      if Model.InsertBeforeEnd(Setter.Block, 'Invalidate;', Edit) then
      begin
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), Message, TRuleConfidence.Medium,
          [TRuleFix.Create('"Invalidate;" einfügen', [Edit])]);
      end
      else
      begin
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), Message, TRuleConfidence.Medium);
      end;
    end;
  end;
end;

{ TComponentFixedPixelsRule }

function TComponentFixedPixelsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-fixed-pixels', TRuleSeverity.Warning,
    'Feste Pixelwerte in Paint oder Resize ohne Skalierung');
end;

/// <summary>Zahlenliteral, dessen erstes Zeichen in AFirst liegt ('0'..'9', bei Farben auch '$')?</summary>
function IsNumberLiteral(ANode: TSyntaxNode; const AFirst: TSysCharSet): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and (ANode.Name <> '') and CharInSet(ANode.Name[1], AFirst);
end;

/// <summary>Ganze Dezimalzahl außer 0, 1 und -1?</summary>
function IsPixelLiteral(ANode: TSyntaxNode): Boolean;
var
  Value: Integer;
begin
  Result := IsNumberLiteral(ANode, ['0'..'9']) and TryStrToInt(ANode.Name, Value) and (Value > 1);
end;

/// <summary>Skaliert der Aufruf seinen Wert? Neben ScaleValue &amp; Co. auch eigene Helfer wie Scale(3) oder
/// ScaleDpi(3), deren Name mit Scale beginnt (#647).</summary>
function IsScaleCall(const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  if LastDelimiter('.', Name) > 0 then
  begin
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  end;
  Result := IsIn(Name, ScaleCalls) or StartsText('Scale', Name);
end;

/// <summary>Methoden der Datei, die selbst skalieren: Ihr Rumpf ruft ScaleValue, MulDiv oder einen Scale…-Helfer
/// auf (eigene Helfer wie Px(6) mit MulDiv(AValue, CurrentPPI, 96)).</summary>
function ScalingHelpers(AModel: TComponentModel): TArray<string>;
var
  mMethod: TMethodImpl;
begin
  Result := nil;
  for mMethod in AModel.Methods do
  begin
    if (mMethod.Block <> nil) and (AModel.HasToken(mMethod.Block, ScaleCalls) or
      AModel.HasTokenStarting(mMethod.Block, 'Scale')) then
    begin
      Result := Result + [mMethod.MethodName];
    end;
  end;
end;

/// <summary>Macht der unmittelbar umgebende Knoten AParent den Wert zu etwas anderem als einem Pixelwert
/// (Faktor, Index, case-Marke, Schleifengrenze, Mengenelement)?</summary>
function DirectExclusion(AParent: TSyntaxNode): Boolean;
begin
  case AParent.Kind of
    TSyntaxKind.BinaryExpr:
      Result := IsIn(AParent.Name, ['*', '/', 'div', 'mod', 'shl', 'shr', 'and', 'or', 'xor']);
    TSyntaxKind.IndexAccess, TSyntaxKind.CaseItem, TSyntaxKind.ForStatement, TSyntaxKind.SetConstructor:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Steht der Wert in einem Zusammenhang, der kein Pixelwert ist oder schon skaliert? AHelpers: eigene
/// Methoden, die skalieren (ScalingHelpers).</summary>
function Excluded(ANode: TSyntaxNode; const AHelpers: TArray<string>): Boolean;
var
  Parent, Child: TSyntaxNode;
  mDone: Boolean;
begin
  Result := False;
  mDone := False;
  Child := ANode;
  Parent := ANode.Parent;
  while (Parent <> nil) and not mDone do
  begin
    mDone := True;
    case Parent.Kind of
      TSyntaxKind.Call:
        begin
          Result := IsScaleCall(Parent.Name) or IsIn(Parent.Name, AHelpers) or
            IsIn(Parent.Name, ['RGB', 'TColor', 'Sleep', 'Inc', 'Dec']);
          mDone := Result;
        end;
      TSyntaxKind.AssignStatement:
        Result := IsIn(Parent.Name, NonPixelTargets);
      TSyntaxKind.Block, TSyntaxKind.RoutineDecl:
        Result := False;
    else
      Result := (Child = ANode) and DirectExclusion(Parent);
      mDone := Result;
    end;
    Child := Parent;
    Parent := Parent.Parent;
  end;
end;

procedure CollectPixels(ANode: TSyntaxNode; AList: TList<TSyntaxNode>; const AHelpers: TArray<string>);
var
  List: TList<TSyntaxNode>;
  mHelpers: TArray<string>;
begin
  List := AList;
  mHelpers := AHelpers;
  // Iterativ (Bericht M1).
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      Result := AVisited.Kind <> TSyntaxKind.AnonymousMethod;
      if Result and IsPixelLiteral(AVisited) and not Excluded(AVisited, mHelpers) then
      begin
        List.Add(AVisited);
      end;
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
  mHelpers: TArray<string>;
begin
  Cache := TRuleDerived.Open(AContext);
  if not PrepareModel(Cache, AContext, Model) then
  begin
    Exit;
  end;
  mHelpers := ScalingHelpers(Model);
  Literals := TList<TSyntaxNode>.Create;
  try
    for Method in Model.Methods do
    begin
      if not IsIn(Method.MethodName, PaintMethods) or not Model.IsComponent(Method.ClassName) then
      begin
        Continue;
      end;
      Literals.Clear;
      CollectPixels(Method.Block, Literals, mHelpers);
      // Ein Treffer je Ausdruck (z. B. Rect(0, 0, 16, 16)), nicht je Zahl.
      Index := 0;
      while Index < Literals.Count do
      begin
        Last := Index;
        while (Last + 1 < Literals.Count) and (Literals[Last + 1].Parent = Literals[Index].Parent) do
        begin
          Inc(Last);
        end;
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
    if not IsNumberLiteral(Argument, ['$', '0'..'9']) then
    begin
      Exit(False);
    end;
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
      begin
        Exit;
      end;
      // RGB(…) und TColor(…) mit Zahlen; TColor(FColors.Surface) wandelt eine Farbe des Themas um (#1109).
      if (AVisited.Kind = TSyntaxKind.Call) and IsIn(AVisited.Name, ['RGB', 'TColor']) then
      begin
        if LiteralArguments(AVisited) then
        begin
          List.Add(AVisited);
        end;
        Exit(False);
      end;
      // $00BBGGRR oder eine Zahl, die einer …Color-Eigenschaft zugewiesen wird
      if IsNumberLiteral(AVisited, ['$', '0'..'9']) and (AVisited.Parent <> nil) and
        (AVisited.Parent.Kind = TSyntaxKind.AssignStatement) and EndsText('Color', AVisited.Parent.Name) then
      begin
        List.Add(AVisited);
      end;
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
  if not PrepareModel(Cache, AContext, Model) then
  begin
    Exit;
  end;
  Colors := TList<TSyntaxNode>.Create;
  try
    for Method in Model.Methods do
    begin
      if not SameText(Method.MethodName, 'Paint') or not Model.IsComponent(Method.ClassName) then
      begin
        Continue;
      end;
      Colors.Clear;
      CollectColors(Method.Block, Colors);
      for Node in Colors do
      begin
        AReport.Add(TTextRange.Create(Node.StartPos, Node.EndPos), 'Feste Farbe in Paint: passt nicht zu ' +
          'VCL-Styles; Systemfarben (clBtnFace …) oder StyleServices.GetSystemColor verwenden',
          TRuleConfidence.Medium);
      end;
    end;
  finally
    Colors.Free;
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

