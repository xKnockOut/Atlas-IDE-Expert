unit Atlas.Common.Rules.Builtin.Components;

// Prüfregeln für VCL-Komponenten (#55, Teil A: alles innerhalb einer Unit):
//   component-missing-inherited          Loaded, Paint, CreateParams … ohne inherited
//   component-default-mismatch           default passt nicht zum Wert im Konstruktor
//   component-missing-free-notification  Komponentenreferenz ohne FreeNotification
//   component-setter-without-invalidate  Setter eines in Paint gelesenen Felds ohne Invalidate
//   component-fixed-pixels               feste Pixelwerte in Paint/Resize ohne ScaleValue
//   component-hardcoded-color            RGB-Literale und TColor-Casts in Paint
//   control-fixed-bounds                 feste Pixelwerte an Width/Height/Left/Top/ClientWidth/
//                                        ClientHeight in VCL-Units ohne ScaleValue (#1982)
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

  TControlFixedBoundsRule = class(TInterfacedObject, IRule)
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
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Components.Model,
  Atlas.Common.Rules.Builtin.Components.InheritedCalls,
  Atlas.Common.Rules.Builtin.Components.Members,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TComponentsText = (InheritedTitle, VclWork, PaintsItself, FiresOnPaint, InsertInherited, DefaultTitle,
    DefaultMismatch, ChangeDefault, FreeNotificationTitle, AddFreeNotification, InvalidateTitle, NoInvalidate,
    InsertInvalidate, PixelTitle, FixedPixel, ScaleWith, ColorTitle, FixedColor, ForeignComponent,
    BoundsTitle, FixedBounds);

const
  cTexts: array[TComponentsText] of TAtlasText = (
    (De: 'Überschriebene Komponentenmethode ruft inherited nicht auf';
     En: 'Overridden component method does not call inherited'),
    (De: '%s.%s ruft inherited nicht auf; die VCL erledigt dort eigene Arbeit';
     En: '%s.%s does not call inherited; the VCL does its own work there'),
    (De: '%s.Paint ruft inherited nicht auf; %s.Paint zeichnet dort selbst';
     En: '%s.Paint does not call inherited; %s.Paint paints itself there'),
    (De: '%s.Paint ruft inherited nicht auf; %s.Paint löst dort OnPaint aus';
     En: '%s.Paint does not call inherited; %s.Paint fires OnPaint there'),
    (De: '"inherited;" einfügen'; En: 'Insert "inherited;"'),
    (De: 'default-Angabe stimmt nicht mit dem Wert im Konstruktor überein';
     En: 'default specifier does not match the value in the constructor'),
    (De: '"%s" hat default %s, der Konstruktor setzt %s aber auf %s; der Wert wird dann nicht in der DFM gespeichert ' +
      'oder falsch geladen';
     En: '"%s" has default %s, but the constructor sets %s to %s; the value is then not stored in the DFM or loaded ' +
      'incorrectly'),
    (De: 'default auf %s ändern'; En: 'Change default to %s'),
    (De: 'Komponentenreferenz ohne FreeNotification'; En: 'Component reference without FreeNotification'),
    (De: 'FreeNotification im Setter ergänzen'; En: 'Add FreeNotification to the setter'),
    (De: 'Setter ändert ein in Paint gelesenes Feld ohne Invalidate';
     En: 'Setter changes a field read in Paint without Invalidate'),
    (De: '%s ändert %s, das Paint liest, ohne Invalidate; die Anzeige bleibt veraltet';
     En: '%s changes %s, which Paint reads, without Invalidate; the display stays outdated'),
    (De: '"Invalidate;" einfügen'; En: 'Insert "Invalidate;"'),
    (De: 'Feste Pixelwerte in Paint oder Resize ohne Skalierung';
     En: 'Fixed pixel values in Paint or Resize without scaling'),
    (De: 'Fester Pixelwert in %s: bei mehr als 96 dpi zu klein; ScaleValue verwenden';
     En: 'Fixed pixel value in %s: too small above 96 dpi; use ScaleValue'),
    (De: 'Mit ScaleValue skalieren'; En: 'Scale with ScaleValue'),
    (De: 'Feste Farbe in Paint statt Systemfarbe oder StyleServices';
     En: 'Fixed color in Paint instead of system color or StyleServices'),
    (De: 'Feste Farbe in Paint: passt nicht zu VCL-Styles; Systemfarben (clBtnFace …) oder ' +
      'StyleServices.GetSystemColor verwenden';
     En: 'Fixed color in Paint: does not fit VCL styles; use system colors (clBtnFace …) or ' +
      'StyleServices.GetSystemColor'),
    (De: '"%s" verweist auf eine fremde Komponente ohne FreeNotification; wird sie freigegeben, bleibt ein ' +
      'ungültiger Zeiger zurück';
     En: '"%s" refers to a foreign component without FreeNotification; when it is freed, a dangling pointer remains'),
    (De: 'Feste Pixelwerte für Größe oder Lage eines Steuerelements';
     En: 'Fixed pixel values for the size or position of a control'),
    (De: '%s erhält einen festen Pixelwert: bei mehr als 96 dpi zu klein; ScaleValue verwenden';
     En: '%s gets a fixed pixel value: too small above 96 dpi; use ScaleValue'));

{$SCOPEDENUMS OFF}

{ TComponentMissingInheritedRule }

function TComponentMissingInheritedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-missing-inherited', TRuleSeverity.Warning,
    cTexts[TComponentsText.InheritedTitle].Text);
end;

/// <summary>Überschreibt AMethod von AClass eine Methode aus InheritedMethods ohne inherited? AToken: Name im
/// Kopf der Implementierung.</summary>
function LacksInherited(AModel: TComponentModel; const AClass: TClassInfo; const AMethod: TMethodImpl;
  out AToken: TPascalToken): Boolean;
begin
  Result := SameText(AMethod.ClassName, AClass.Name) and IsIn(AMethod.MethodName, cInheritedMethods) and
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
  AMessage := cTexts[TComponentsText.VclWork].Fmt([AClassName, AMethodName]);
  Result := not SameText(AMethodName, 'Paint');
  if Result or not AModel.PaintingAncestor(AClassName, mAncestor, mOnPaintOnly) then
  begin
    Exit;
  end;
  AConfidence := TRuleConfidence.Medium;
  if not mOnPaintOnly then
  begin
    AMessage := cTexts[TComponentsText.PaintsItself].Fmt([AClassName, mAncestor]);
  end
  else
  begin
    AMessage := cTexts[TComponentsText.FiresOnPaint].Fmt([AClassName, mAncestor]);
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
      [TRuleFix.Create(cTexts[TComponentsText.InsertInherited].Text, [mEdit])]);
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
    cTexts[TComponentsText.DefaultTitle].Text);
end;

/// <summary>Zuweisung an AField im Block (Feld oder Self.Feld); der zugewiesene Ausdruck.</summary>
function FindAssignment(ANode: TSyntaxNode; const AField: string; out AValue: TSyntaxNode): Boolean;
var
  mField: string;
  mFound: TSyntaxNode;
begin
  mField := AField;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht); out-Parameter lassen sich nicht in der anonymen Methode verwenden.
  mFound := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    var
      Target: TSyntaxNode;
    begin
      if (AVisited.Kind = TSyntaxKind.AssignStatement) and (AVisited.ChildCount = 2) and
        SameText(AVisited.Name, mField) then
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
  Result := mFound <> nil;
  if Result then
  begin
    AValue := mFound[1];
  end;
end;

/// <summary>Gleicher Wert? Zahlen werden verglichen ($-Hex wie dezimal), sonst der Text.</summary>
function SameValue(const A, B: string): Boolean;
var
  mNumberA, mNumberB: Int64;
begin
  if TryStrToInt64(A, mNumberA) and TryStrToInt64(B, mNumberB) then
  begin
    Result := mNumberA = mNumberB;
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
      AReport.Add(mRange, cTexts[TComponentsText.DefaultMismatch].Fmt([mProp.Name, mProp.DefaultText, mProp.ReadName,
        mValueText]), TRuleConfidence.High,
        [TRuleFix.Create(cTexts[TComponentsText.ChangeDefault].Fmt([mValueText]), [TRuleEdit.Create(mRange,
          mValueText)])]);
    end;
  end;
end;

{ TComponentMissingFreeNotificationRule }

function TComponentMissingFreeNotificationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-missing-free-notification', TRuleSeverity.Warning,
    cTexts[TComponentsText.FreeNotificationTitle].Text);
end;

/// <summary>Name des letzten Parameters der Implementierung.</summary>
function LastParameter(const AMethod: TMethodImpl): string;
var
  mHeader, mParams: TSyntaxNode;
begin
  Result := '';
  mHeader := AMethod.Decl.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  mParams := mHeader.FindChild(TSyntaxKind.Parameters);
  if (mParams <> nil) and (mParams.ChildCount > 0) then
  begin
    Result := mParams[mParams.ChildCount - 1].Name;
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
      AReport.Add(mRange, cTexts[TComponentsText.ForeignComponent].Fmt([AProp.Name]), TRuleConfidence.Medium);
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
    AReport.Add(mRange, cTexts[TComponentsText.ForeignComponent].Fmt([AProp.Name]), TRuleConfidence.Medium,
      [TRuleFix.Create(cTexts[TComponentsText.AddFreeNotification].Text, [mEdit])]);
  end
  else
  begin
    AReport.Add(mRange, cTexts[TComponentsText.ForeignComponent].Fmt([AProp.Name]), TRuleConfidence.Medium);
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
    cTexts[TComponentsText.InvalidateTitle].Text);
end;

/// <summary>Setzt der Setter von AProp das Feld, das Paint liest, ohne neu zu zeichnen? ASetter: der Setter.</summary>
function SetterMissesRepaint(AModel: TComponentModel; const AInfo: TClassInfo; const AProp: TPropertyInfo;
  const APaint: TMethodImpl; out ASetter: TMethodImpl): Boolean;
var
  mValue: TSyntaxNode;
begin
  Result := (AProp.ReadName <> '') and AModel.FindMethod(AInfo.Name, AProp.WriteName, ASetter) and
    FindAssignment(ASetter.Block, AProp.ReadName, mValue) and
    AModel.HasToken(APaint.Block, [AProp.ReadName, AProp.Name]) and not AModel.HasToken(ASetter.Block, cRepaintCalls);
end;

procedure TComponentSetterWithoutInvalidateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mInfo: TClassInfo;
  mProp: TPropertyInfo;
  mSetter, mPaint: TMethodImpl;
  mToken: TPascalToken;
  mEdit: TRuleEdit;
  mMessage: string;
begin
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  for mInfo in mModel.Classes do
  begin
    if not mModel.IsComponent(mInfo.Name) or not mModel.FindMethod(mInfo.Name, 'Paint', mPaint) then
    begin
      Continue;
    end;
    for mProp in mModel.Properties(mInfo) do
    begin
      if not SetterMissesRepaint(mModel, mInfo, mProp, mPaint, mSetter) or not mModel.NameToken(mSetter, mToken) then
      begin
        Continue;
      end;
      mMessage := cTexts[TComponentsText.NoInvalidate].Fmt([mSetter.MethodName, mProp.ReadName]);
      if mModel.InsertBeforeEnd(mSetter.Block, 'Invalidate;', mEdit) then
      begin
        AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), mMessage, TRuleConfidence.Medium,
          [TRuleFix.Create(cTexts[TComponentsText.InsertInvalidate].Text, [mEdit])]);
      end
      else
      begin
        AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), mMessage, TRuleConfidence.Medium);
      end;
    end;
  end;
end;

{ TComponentFixedPixelsRule }

function TComponentFixedPixelsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-fixed-pixels', TRuleSeverity.Warning,
    cTexts[TComponentsText.PixelTitle].Text);
end;

/// <summary>Zahlenliteral, dessen erstes Zeichen in AFirst liegt ('0'..'9', bei Farben auch '$')?</summary>
function IsNumberLiteral(ANode: TSyntaxNode; const AFirst: TSysCharSet): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and (ANode.Name <> '') and CharInSet(ANode.Name[1], AFirst);
end;

/// <summary>Ganze Dezimalzahl außer 0, 1 und -1?</summary>
function IsPixelLiteral(ANode: TSyntaxNode): Boolean;
var
  mValue: Integer;
begin
  Result := IsNumberLiteral(ANode, ['0'..'9']) and TryStrToInt(ANode.Name, mValue) and (mValue > 1);
end;

/// <summary>Skaliert der Aufruf seinen Wert? Neben ScaleValue &amp; Co. auch eigene Helfer wie Scale(3) oder
/// ScaleDpi(3), deren Name mit Scale beginnt (#647).</summary>
function IsScaleCall(const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  if LastDelimiter('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  Result := IsIn(mName, cScaleCalls) or StartsText('Scale', mName);
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
    if (mMethod.Block <> nil) and (AModel.HasToken(mMethod.Block, cScaleCalls) or
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
  mParent, mChild: TSyntaxNode;
  mDone: Boolean;
begin
  Result := False;
  mDone := False;
  mChild := ANode;
  mParent := ANode.Parent;
  while (mParent <> nil) and not mDone do
  begin
    mDone := True;
    case mParent.Kind of
      TSyntaxKind.Call:
        begin
          Result := IsScaleCall(mParent.Name) or IsIn(mParent.Name, AHelpers) or
            IsIn(mParent.Name, ['RGB', 'TColor', 'Sleep', 'Inc', 'Dec']);
          mDone := Result;
        end;
      TSyntaxKind.AssignStatement:
        Result := IsIn(mParent.Name, cNonPixelTargets);
      TSyntaxKind.Block, TSyntaxKind.RoutineDecl:
        Result := False;
    else
      Result := (mChild = ANode) and DirectExclusion(mParent);
      mDone := Result;
    end;
    mChild := mParent;
    mParent := mParent.Parent;
  end;
end;

procedure CollectPixels(ANode: TSyntaxNode; AList: TList<TSyntaxNode>; const AHelpers: TArray<string>);
var
  mList: TList<TSyntaxNode>;
  mHelpers: TArray<string>;
begin
  mList := AList;
  mHelpers := AHelpers;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      Result := AVisited.Kind <> TSyntaxKind.AnonymousMethod;
      if Result and IsPixelLiteral(AVisited) and not Excluded(AVisited, mHelpers) then
      begin
        mList.Add(AVisited);
      end;
    end);
end;

procedure TComponentFixedPixelsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mMethod: TMethodImpl;
  mLiterals: TList<TSyntaxNode>;
  mIndex, mLast: Integer;
  mEdits: TArray<TRuleEdit>;
  mLiteral: TSyntaxNode;
  mHelpers: TArray<string>;
begin
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  mHelpers := ScalingHelpers(mModel);
  mLiterals := TList<TSyntaxNode>.Create;
  try
    for mMethod in mModel.Methods do
    begin
      if not IsIn(mMethod.MethodName, cPaintMethods) or not mModel.IsComponent(mMethod.ClassName) then
      begin
        Continue;
      end;
      mLiterals.Clear;
      CollectPixels(mMethod.Block, mLiterals, mHelpers);
      // Ein Treffer je Ausdruck (z. B. Rect(0, 0, 16, 16)), nicht je Zahl.
      mIndex := 0;
      while mIndex < mLiterals.Count do
      begin
        mLast := mIndex;
        while (mLast + 1 < mLiterals.Count) and (mLiterals[mLast + 1].Parent = mLiterals[mIndex].Parent) do
        begin
          Inc(mLast);
        end;
        mEdits := nil;
        while mIndex <= mLast do
        begin
          mLiteral := mLiterals[mIndex];
          mEdits := mEdits + [TRuleEdit.Create(TTextRange.Create(mLiteral.StartPos, mLiteral.EndPos),
            'ScaleValue(' + mLiteral.Name + ')')];
          Inc(mIndex);
        end;
        AReport.Add(TTextRange.Create(mLiterals[mLast - Length(mEdits) + 1].StartPos, mLiterals[mLast].EndPos),
          cTexts[TComponentsText.FixedPixel].Fmt(
          [mMethod.MethodName]), TRuleConfidence.Medium, [TRuleFix.Create(cTexts[TComponentsText.ScaleWith].Text,
            mEdits)]);
      end;
    end;
  finally
    mLiterals.Free;
  end;
end;

{ TComponentHardcodedColorRule }

function TComponentHardcodedColorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-hardcoded-color', TRuleSeverity.Hint,
    cTexts[TComponentsText.ColorTitle].Text);
end;

/// <summary>Sind alle Argumente des Aufrufs ACall Zahlenliterale (RGB(255, 0, 0), TColor($00FF00))?</summary>
function LiteralArguments(ACall: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mArgument: TSyntaxNode;
begin
  Result := ACall.ChildCount > 1;
  for mIndex := 1 to ACall.ChildCount - 1 do
  begin
    mArgument := ACall[mIndex];
    if not IsNumberLiteral(mArgument, ['$', '0'..'9']) then
    begin
      Exit(False);
    end;
  end;
end;

procedure CollectColors(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  mList: TList<TSyntaxNode>;
begin
  mList := AList;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
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
          mList.Add(AVisited);
        end;
        Exit(False);
      end;
      // $00BBGGRR oder eine Zahl, die einer …Color-Eigenschaft zugewiesen wird
      if IsNumberLiteral(AVisited, ['$', '0'..'9']) and (AVisited.Parent <> nil) and
        (AVisited.Parent.Kind = TSyntaxKind.AssignStatement) and EndsText('Color', AVisited.Parent.Name) then
      begin
        mList.Add(AVisited);
      end;
    end);
end;

procedure TComponentHardcodedColorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mMethod: TMethodImpl;
  mColors: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  mColors := TList<TSyntaxNode>.Create;
  try
    for mMethod in mModel.Methods do
    begin
      if not SameText(mMethod.MethodName, 'Paint') or not mModel.IsComponent(mMethod.ClassName) then
      begin
        Continue;
      end;
      mColors.Clear;
      CollectColors(mMethod.Block, mColors);
      for mNode in mColors do
      begin
        AReport.Add(TTextRange.Create(mNode.StartPos, mNode.EndPos), cTexts[TComponentsText.FixedColor].Text,
          TRuleConfidence.Medium);
      end;
    end;
  finally
    mColors.Free;
  end;
end;
{ TControlFixedBoundsRule }

const
  // Eigenschaften, die Größe oder Lage in Pixeln angeben.
  cBoundsTargets: array[0..5] of string = ('Width', 'Height', 'Left', 'Top', 'ClientWidth', 'ClientHeight');
  // Zeichenwerkzeuge und Schrift: Pen.Width gehört zu Paint (component-fixed-pixels), Font.Height skaliert die
  // VCL mit der Schrift.
  cDrawingOwners: array[0..3] of string = ('Pen', 'Canvas', 'Brush', 'Font');
  // Teile eines Steuerelements ohne eigenes ScaleValue: skaliert wird über das Steuerelement davor.
  cControlParts: array[0..2] of string = ('Margins', 'Padding', 'Constraints');
  // Ab hier ist Top/Left eine Reihenfolge für Align (alTop/alBottom), kein Pixelwert.
  cAlignOrder = 10000;

function TControlFixedBoundsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('control-fixed-bounds', TRuleSeverity.Warning,
    cTexts[TComponentsText.BoundsTitle].Text);
end;

/// <summary>Bindet die Unit eine VCL-Unit ein (Vcl.* oder ohne Namespace Controls/Forms)?</summary>
function UsesVcl(const AContext: TRuleContext): Boolean;
var
  mUnit: string;
begin
  Result := False;
  for mUnit in TUsesClauses.UsedUnits(AContext.Tree.Tokens) do
  begin
    if StartsText('Vcl.', mUnit) or SameText(mUnit, 'Controls') or SameText(mUnit, 'Forms') then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Setzt die Zuweisung AAssign Größe oder Lage (Width, Left …), nicht aber Pen.Width &amp; Co.?</summary>
function IsBoundsAssign(AAssign: TSyntaxNode): Boolean;
var
  mTarget: TSyntaxNode;
begin
  Result := (AAssign.Kind = TSyntaxKind.AssignStatement) and IsIn(AAssign.Name, cBoundsTargets) and
    (AAssign.ChildCount = 2);
  if Result then
  begin
    mTarget := AAssign.Children[0];
    Result := (mTarget.Kind <> TSyntaxKind.MemberAccess) or (mTarget.ChildCount = 0) or
      not IsIn(mTarget.Children[0].Name, cDrawingOwners);
  end;
end;

/// <summary>Pixelwert der Zuweisung AAssign? Nicht bei Zahlen ab cAlignOrder, nicht in einem Produkt oder
/// Quotienten (Zeilenzahl mal Zeilenhöhe) und nicht als Argument eines Aufrufs außer Min und Max (AddPanel(30)
/// legt selbst fest, was die Zahl ist).</summary>
function IsBoundsLiteral(ANode, AAssign: TSyntaxNode): Boolean;
var
  mValue: Integer;
  mParent: TSyntaxNode;
begin
  Result := TryStrToInt(ANode.Name, mValue) and (mValue < cAlignOrder);
  mParent := ANode.Parent;
  while Result and (mParent <> nil) and (mParent <> AAssign) do
  begin
    case mParent.Kind of
      TSyntaxKind.BinaryExpr:
        Result := not IsIn(mParent.Name, ['*', '/', 'div', 'mod', 'shl', 'shr']);
      TSyntaxKind.Call:
        Result := IsIn(mParent.Name, ['Max', 'Min']);
    end;
    mParent := mParent.Parent;
  end;
end;

/// <summary>Aufruf, der AValue für das Ziel der Zuweisung AAssign skaliert: ScaleValue des Steuerelements, dem
/// Width &amp; Co. gehören (bei Margins, Padding und Constraints das davor), ohne Objekt das eigene. Das Ziel selbst
/// skaliert richtig, ob es schon eingehängt ist oder erst beim Einhängen mitskaliert wird.</summary>
function ScaleCallFor(const AContext: TRuleContext; AAssign: TSyntaxNode; const AValue: string): string;
var
  mOwner: TSyntaxNode;
begin
  mOwner := AAssign.Children[0];
  if (mOwner.Kind <> TSyntaxKind.MemberAccess) or (mOwner.ChildCount = 0) then
  begin
    Exit('ScaleValue(' + AValue + ')');
  end;
  mOwner := mOwner.Children[0];
  if (mOwner.Kind = TSyntaxKind.MemberAccess) and (mOwner.ChildCount > 0) and IsIn(mOwner.Name, cControlParts) then
  begin
    mOwner := mOwner.Children[0];
  end;
  // Ein Aufruf als Ziel (NewLabel(…).Top) würde doppelt ausgeführt: dann über Self.
  if mOwner.Kind = TSyntaxKind.Call then
  begin
    Exit('ScaleValue(' + AValue + ')');
  end;
  Result := Copy(AContext.Text, mOwner.StartOffset + 1, mOwner.EndOffset - mOwner.StartOffset) + '.ScaleValue(' +
    AValue + ')';
end;

/// <summary>Liegt ANode in Paint oder Resize einer Komponente? Dort meldet component-fixed-pixels.</summary>
function InPaintMethod(AModel: TComponentModel; ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
  mName: string;
begin
  Result := False;
  mNode := ANode.Parent;
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    mNode := mNode.Parent;
  end;
  if (mNode <> nil) and (LastDelimiter('.', mNode.Name) > 0) then
  begin
    mName := Copy(mNode.Name, LastDelimiter('.', mNode.Name) + 1, MaxInt);
    Result := IsIn(mName, cPaintMethods) and
      AModel.IsComponent(Copy(mNode.Name, 1, LastDelimiter('.', mNode.Name) - 1));
  end;
end;

procedure TControlFixedBoundsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TComponentModel;
  mCache: IRuleDerivedCache;
  mAssigns, mLiterals: TList<TSyntaxNode>;
  mAssign, mLiteral: TSyntaxNode;
  mHelpers: TArray<string>;
  mEdits: TArray<TRuleEdit>;
  mIndex: Integer;
begin
  if (AContext.Tree = nil) or not UsesVcl(AContext) then
  begin
    Exit;
  end;
  mCache := TRuleDerived.Open(AContext);
  if not PrepareModel(mCache, AContext, mModel) then
  begin
    Exit;
  end;
  mHelpers := ScalingHelpers(mModel);
  mAssigns := TList<TSyntaxNode>.Create;
  mLiterals := TList<TSyntaxNode>.Create;
  try
    AContext.Tree.Root.Walk(
      function(AVisited: TSyntaxNode): Boolean
      begin
        Result := True;
        if IsBoundsAssign(AVisited) then
        begin
          mAssigns.Add(AVisited);
        end;
      end);
    for mAssign in mAssigns do
    begin
      if InPaintMethod(mModel, mAssign) then
      begin
        Continue;
      end;
      mLiterals.Clear;
      CollectPixels(mAssign.Children[1], mLiterals, mHelpers);
      for mIndex := mLiterals.Count - 1 downto 0 do
      begin
        if not IsBoundsLiteral(mLiterals[mIndex], mAssign) then
        begin
          mLiterals.Delete(mIndex);
        end;
      end;
      if mLiterals.Count = 0 then
      begin
        Continue;
      end;
      mEdits := nil;
      for mLiteral in mLiterals do
      begin
        mEdits := mEdits + [TRuleEdit.Create(TTextRange.Create(mLiteral.StartPos, mLiteral.EndPos),
          ScaleCallFor(AContext, mAssign, mLiteral.Name))];
      end;
      AReport.Add(TTextRange.Create(mLiterals.First.StartPos, mLiterals.Last.EndPos),
        cTexts[TComponentsText.FixedBounds].Fmt([mAssign.Name]), TRuleConfidence.Medium,
        [TRuleFix.Create(cTexts[TComponentsText.ScaleWith].Text, mEdits)]);
    end;
  finally
    mLiterals.Free;
    mAssigns.Free;
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
  ARegistry.Register(TControlFixedBoundsRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Components', cTexts);

end.

