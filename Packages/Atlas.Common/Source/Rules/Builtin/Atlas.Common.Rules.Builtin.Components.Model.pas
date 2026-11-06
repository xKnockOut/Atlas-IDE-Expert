unit Atlas.Common.Rules.Builtin.Components.Model;

// Gemeinsames Modell der Komponentenregeln (Atlas.Common.Rules.Builtin.Components): Klassen, Methoden und
// Eigenschaften der geprüften Datei, Vorfahrenkette und Einfügehilfen für Korrekturen; dazu die Listen bekannter
// VCL-Klassen und Methoden.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Builtin.Inheritance;

const
  // Bekannte VCL-Basisklassen; erreicht die Vorfahrenkette eine davon, gilt die Klasse
  // als Komponente, auch wenn RTL und VCL nicht im Index stehen.
  cComponentBases: array[0..21] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TCustomPanel', 'TPanel', 'TCustomForm', 'TForm', 'TCustomFrame', 'TFrame',
    'TDataModule', 'TScrollingWinControl', 'TCustomListBox', 'TCustomEdit', 'TCustomComboBox',
    'TButtonControl', 'TCustomLabel', 'TImage', 'TDataSource', 'TDataSet', 'TCustomImageList');
  // Methoden, die im Nachfahren inherited aufrufen müssen.
  cInheritedMethods: array[0..6] of string = ('Loaded', 'CreateParams', 'CreateWnd', 'Notification',
    'SetParent', 'Destroy', 'Paint');
  // Vorfahren, deren Paint leer ist oder die gar kein Paint haben: TCustomControl.Paint und TGraphicControl.Paint
  // tun nichts, ein Paint ohne inherited ist dort das übliche Muster.
  cEmptyPaintBases: array[0..9] of string = ('TCustomControl', 'TGraphicControl', 'TWinControl', 'TControl',
    'TComponent', 'TPersistent', 'TObject', 'TScrollingWinControl', 'TCustomFrame', 'TFrame');
  // VCL-Vorfahren, deren Paint selbst zeichnet (Rahmen, Hintergrund, Text, Bild).
  cDrawingPaintBases: array[0..17] of string = ('TCustomPanel', 'TPanel', 'TCustomGridPanel', 'TGridPanel',
    'TCustomFlowPanel', 'TFlowPanel', 'TImage', 'TShape', 'TBevel', 'TCustomLabel', 'TLabel', 'TSpeedButton',
    'TSplitter', 'TCustomGrid', 'TCustomDrawGrid', 'TDrawGrid', 'TStringGrid', 'TCustomStaticText');
  // VCL-Vorfahren, deren Paint zur Laufzeit nur OnPaint auslöst (im Designer dazu Raster bzw. Strichrahmen).
  // Ohne inherited fehlt dort nur OnPaint; das zählt erst, wenn die Unit OnPaint benutzt oder ein DFM hat.
  cOnPaintPaintBases: array[0..2] of string = ('TCustomForm', 'TForm', 'TPaintBox');
  // RTL- und VCL-Klassen mit eigenem Konstruktor, auch wenn sie nicht im Index stehen (#919).
  cConstructorBases: array[0..13] of string = ('TThread', 'TStrings', 'TStringList', 'TList', 'TObjectList',
    'TDictionary', 'TObjectDictionary', 'TQueue', 'TStack', 'TStream', 'TFileStream', 'TMemoryStream',
    'TStringStream', 'TInterfacedPersistent');
  // Konstruktoren der VCL-Vorfahren, die ein Konstruktor ohne inherited aufrufen darf: CreateNew legt ein Formular
  // ohne DFM an und ruft selbst inherited Create (#1109).
  cAncestorConstructors: array[0..2] of string = ('CreateNew', 'CreateParented', 'CreateParentedControl');
  // Methoden, in denen Pixelwerte und Farben geprüft werden.
  cPaintMethods: array[0..1] of string = ('Paint', 'Resize');
  // Aufrufe, deren Argumente schon skaliert werden.
  cScaleCalls: array[0..5] of string = ('ScaleValue', 'MulDiv', 'ScaleX', 'ScaleY', 'ScaleRect', 'ScaleSize');
  // Aufrufe, die ein Neuzeichnen veranlassen.
  cRepaintCalls: array[0..6] of string = ('Invalidate', 'Repaint', 'Refresh', 'Update', 'Changed', 'Change',
    'InvalidateRect');
  // Zuweisungen an diese Eigenschaften sind keine Pixelwerte.
  cNonPixelTargets: array[0..6] of string = ('Size', 'Color', 'Tag', 'Style', 'Mode', 'Charset', 'Orientation');

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
    function DeclaresPaint(const AClassName: string): Boolean;
    function PropertyOf(ADecl: TSyntaxNode): TPropertyInfo;
    function BlockTokens(ABlock: TSyntaxNode; out AFirst, ALast: TPascalToken): Boolean;
  public
    /// <summary>ALocal ist der Index der Datei (TRuleDerived.UnitIndex). Das Modell liest aus AContext
    /// nur Tree und Text; es wird über den Ableitungscache von allen Komponentenregeln geteilt.</summary>
    constructor Create(const AContext: TRuleContext; const ALocal: TUnitIndex);
    destructor Destroy; override;
    function IsComponent(const AClassName: string): Boolean;
    /// <summary>Nächster Vorfahr von AClassName, dessen Paint selbst zeichnet: bekannte VCL-Klasse aus
    /// DrawingPaintBases oder eine Klasse aus Datei oder Index, die Paint selbst deklariert. False, wenn zuerst ein
    /// Vorfahr mit leerem Paint (TCustomControl, TGraphicControl) kommt oder die Kette abbricht. AOnPaintOnly: Der
    /// Vorfahr stammt aus OnPaintPaintBases (TForm, TPaintBox), sein Paint löst nur OnPaint aus.</summary>
    function PaintingAncestor(const AClassName: string; out AAncestor: string; out AOnPaintOnly: Boolean): Boolean;
    /// <summary>Kann OnPaint in dieser Unit belegt sein: Bezeichner OnPaint im Quelltext oder {$R} mit .dfm
    /// (die Belegung stünde dann im DFM).</summary>
    function MayUseOnPaint: Boolean;
    function FindMethod(const AClassName, AMethodName: string; out AMethod: TMethodImpl): Boolean;
    function DeclaredWith(const AClass: TClassInfo; const AMethodName, ADirective: string): Boolean;
    function Properties(const AClass: TClassInfo): TArray<TPropertyInfo>;
    function HasToken(ANode: TSyntaxNode; const AWords: array of string): Boolean;
    /// <summary>Wie HasToken für Bezeichner, die mit APrefix beginnen (Scale…).</summary>
    function HasTokenStarting(ANode: TSyntaxNode; const APrefix: string): Boolean;
    function NodeText(ANode: TSyntaxNode): string;
    function NameToken(const AMethod: TMethodImpl; out AToken: TPascalToken): Boolean;
    function InsertAfterBegin(ABlock: TSyntaxNode; const AText: string; out AEdit: TRuleEdit): Boolean;
    function InsertBeforeEnd(ABlock: TSyntaxNode; const AText: string; out AEdit: TRuleEdit): Boolean;
    property Classes: TList<TClassInfo> read FClasses;
    property Methods: TList<TMethodImpl> read FMethods;
    property Ancestry: TAncestry read FAncestry;
    property LineBreak: string read FLineBreak;
  end;

/// <summary>Ist AText (ohne Groß-/Kleinschreibung) eines der Wörter AWords?</summary>
function IsIn(const AText: string; const AWords: array of string): Boolean;

/// <summary>Modell der Datei, je Lauf einmal gebaut (Review P-03); gehört ACache, nie freigeben.
/// False ohne Syntaxbaum.</summary>
function PrepareModel(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
  out AModel: TComponentModel): Boolean;

/// <summary>Direkter Vorfahr laut Klassendeklaration; '' ohne Angabe (TObject).</summary>
function DeclaredParent(const AClass: TClassInfo): string;

/// <summary>Namen der Felder der Klasse (auch "FA, FB: T").</summary>
function OwnFields(const AClass: TClassInfo): TArray<string>;

/// <summary>Namen der Kinder von ASection ("A, B: T" ergibt A und B); nil ohne Abschnitt.</summary>
function SectionNames(ASection: TSyntaxNode): TArray<string>;

/// <summary>Parameter und lokale Variablen (var-Abschnitte) einer Methode.</summary>
function MethodLocalNames(const AMethod: TMethodImpl): TArray<string>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Editing.UsesClause,
  Atlas.Text.Lines;

function IsIn(const AText: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    if SameText(AText, mWord) then
    begin
      Exit(True);
    end;
  end;
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
        begin
          FClasses.Add(Info);
        end;
      end
      else if AVisited.Kind = TSyntaxKind.RoutineDecl then
      begin
        Dot := LastDelimiter('.', AVisited.Name);
        Method.Block := AVisited.FindChild(TSyntaxKind.Block);
        if (Dot > 0) and (Method.Block <> nil) then
        begin
          Method.ClassName := Copy(AVisited.Name, 1, Dot - 1);
          if Pos('<', Method.ClassName) > 0 then
          begin
            Method.ClassName := Copy(Method.ClassName, 1, Pos('<', Method.ClassName) - 1);
          end;
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
  mName: string;
  mDepth: Integer;
begin
  mName := AClassName;
  mDepth := 0;
  while (mName <> '') and (mDepth < 64) do
  begin
    if IsIn(mName, cComponentBases) then
    begin
      Exit(True);
    end;
    if SameText(mName, 'TObject') then
    begin
      Break;
    end;
    mName := FAncestry.ParentOf(mName);
    Inc(mDepth);
  end;
  Result := False;
end;

/// <summary>Deklariert die Klasse AClassName aus Datei oder Index selbst Paint?</summary>
function TComponentModel.DeclaresPaint(const AClassName: string): Boolean;
var
  mType: TSymbolLocation;
  mSymbol: TIndexSymbol;
begin
  Result := False;
  if FAncestry.FindClass(AClassName, mType) then
  begin
    for mSymbol in FAncestry.Methods(mType) do
    begin
      Result := Result or SameText(mSymbol.Name, 'Paint');
    end;
  end;
end;

function TComponentModel.PaintingAncestor(const AClassName: string; out AAncestor: string;
  out AOnPaintOnly: Boolean): Boolean;
var
  mName: string;
  mDepth: Integer;
begin
  AAncestor := '';
  AOnPaintOnly := False;
  Result := False;
  mName := FAncestry.ParentOf(AClassName);
  mDepth := 0;
  // Bekannte VCL-Klassen zuerst: Steht die VCL im Index, deklariert auch TCustomControl ein (leeres) Paint.
  while (mName <> '') and (mDepth < 64) and not Result and not IsIn(mName, cEmptyPaintBases) do
  begin
    AOnPaintOnly := IsIn(mName, cOnPaintPaintBases);
    Result := IsIn(mName, cDrawingPaintBases) or AOnPaintOnly or DeclaresPaint(mName);
    if Result then
    begin
      AAncestor := mName;
    end
    else
    begin
      mName := FAncestry.ParentOf(mName);
    end;
    Inc(mDepth);
  end;
end;

function TComponentModel.MayUseOnPaint: Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in FContext.Tree.Tokens do
  begin
    if ((mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, 'OnPaint')) or
      ((mToken.Kind = TPascalTokenKind.Directive) and ContainsText(mToken.Text, '.dfm')) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TComponentModel.FindMethod(const AClassName, AMethodName: string; out AMethod: TMethodImpl): Boolean;
var
  mMethod: TMethodImpl;
begin
  for mMethod in FMethods do
  begin
    if SameText(mMethod.ClassName, AClassName) and SameText(mMethod.MethodName, AMethodName) then
    begin
      AMethod := mMethod;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TComponentModel.DeclaredWith(const AClass: TClassInfo; const AMethodName, ADirective: string): Boolean;
var
  mIndex, mInner: Integer;
  mHeader: TSyntaxNode;
begin
  for mIndex := 0 to AClass.Body.ChildCount - 1 do
  begin
    mHeader := AClass.Body[mIndex];
    if (mHeader.Kind <> TSyntaxKind.RoutineHeader) or not SameText(mHeader.Name, AMethodName) then
    begin
      Continue;
    end;
    for mInner := 0 to mHeader.ChildCount - 1 do
    begin
      if (mHeader[mInner].Kind = TSyntaxKind.Directive) and SameText(mHeader[mInner].Name, ADirective) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Wert hinter read, write oder default (AMode) in AInfo übernehmen; AFirst: erstes Token des
/// Werts.</summary>
procedure AddPropertyValue(var AInfo: TPropertyInfo; const AMode: string; AFirst: Boolean;
  const AToken: TPascalToken);
begin
  case IndexStr(AMode, ['read', 'write', 'default']) of
    0:
      if AFirst then
      begin
        AInfo.ReadName := AToken.Text;
      end;
    1:
      if AFirst then
      begin
        AInfo.WriteName := AToken.Text;
      end;
    2:
      begin
        if AFirst then
        begin
          AInfo.DefaultFirst := AToken;
        end;
        AInfo.DefaultLast := AToken;
        AInfo.DefaultText := AInfo.DefaultText + AToken.Text;
        AInfo.HasDefault := True;
      end;
  else
    // Übrige Angaben (stored, index …) bleiben unbeachtet.
  end;
end;

/// <summary>Eigenschaft ADecl mit read/write/default aus den Token.</summary>
function TComponentModel.PropertyOf(ADecl: TSyntaxNode): TPropertyInfo;
var
  mTokenIndex, mCount: Integer;
  mTypeRef: TSyntaxNode;
  mTokens: TArray<TPascalToken>;
  mToken: TPascalToken;
  mMode: string;
begin
  Result := Default(TPropertyInfo);
  Result.Name := ADecl.Name;
  mTypeRef := ADecl.FindChild(TSyntaxKind.TypeReference);
  if mTypeRef <> nil then
  begin
    Result.TypeName := mTypeRef.Name;
  end;
  mTokens := FContext.Tree.Tokens;
  mMode := '';
  mCount := 0;
  mTokenIndex := TSyntaxTree.FirstTokenOf(mTokens, ADecl.StartOffset);
  while (mTokenIndex <= High(mTokens)) and (mTokens[mTokenIndex].Offset < ADecl.EndOffset) do
  begin
    mToken := mTokens[mTokenIndex];
    Inc(mTokenIndex);
    if (mToken.Offset < ADecl.StartOffset) or (mToken.Kind = TPascalTokenKind.Comment) then
    begin
      Continue;
    end;
    if (Result.NameToken.Text = '') and (mToken.Kind = TPascalTokenKind.Identifier) and
      SameText(mToken.Text, ADecl.Name) then
    begin
      Result.NameToken := mToken;
    end;
    if mToken.IsSymbol(';') then
    begin
      mMode := '';
    end
    else if IsIn(mToken.Text, ['read', 'write', 'default', 'stored', 'nodefault', 'implements', 'index']) then
    begin
      mMode := LowerCase(mToken.Text);
      mCount := 0;
    end
    else
    begin
      AddPropertyValue(Result, mMode, mCount = 0, mToken);
      Inc(mCount);
    end;
  end;
  // Mehrteilige Feldzugriffe (FData.Wert) sind kein einfaches Feld.
  if Pos('.', Result.ReadName) > 0 then
  begin
    Result.ReadName := '';
  end;
end;

function TComponentModel.Properties(const AClass: TClassInfo): TArray<TPropertyInfo>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AClass.Body.ChildCount - 1 do
  begin
    if AClass.Body[mIndex].Kind = TSyntaxKind.PropertyDecl then
    begin
      Result := Result + [PropertyOf(AClass.Body[mIndex])];
    end;
  end;
end;

function TComponentModel.HasToken(ANode: TSyntaxNode; const AWords: array of string): Boolean;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  for mIndex := FContext.Tree.FirstTokenFrom(ANode.StartOffset) to High(FContext.Tree.Tokens) do
  begin
    mToken := FContext.Tree.Tokens[mIndex];
    if mToken.Offset < ANode.StartOffset then
    begin
      Continue;
    end;
    if mToken.Offset >= ANode.EndOffset then
    begin
      Break;
    end;
    if (mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and IsIn(mToken.Text, AWords) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TComponentModel.HasTokenStarting(ANode: TSyntaxNode; const APrefix: string): Boolean;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  for mIndex := FContext.Tree.FirstTokenFrom(ANode.StartOffset) to High(FContext.Tree.Tokens) do
  begin
    mToken := FContext.Tree.Tokens[mIndex];
    if mToken.Offset < ANode.StartOffset then
    begin
      Continue;
    end;
    if mToken.Offset >= ANode.EndOffset then
    begin
      Break;
    end;
    if (mToken.Kind = TPascalTokenKind.Identifier) and StartsText(APrefix, mToken.Text) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TComponentModel.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TComponentModel.NameToken(const AMethod: TMethodImpl; out AToken: TPascalToken): Boolean;
var
  mHeader: TSyntaxNode;
  mToken: TPascalToken;
  mIndex: Integer;
begin
  mHeader := AMethod.Decl.FindChild(TSyntaxKind.RoutineHeader);
  Result := False;
  if mHeader = nil then
  begin
    Exit;
  end;
  // Der letzte passende Bezeichner im Kopf vor der Parameterliste.
  for mIndex := FContext.Tree.FirstTokenFrom(mHeader.StartOffset) to High(FContext.Tree.Tokens) do
  begin
    mToken := FContext.Tree.Tokens[mIndex];
    if mToken.Offset < mHeader.StartOffset then
    begin
      Continue;
    end;
    if (mToken.Offset >= mHeader.EndOffset) or mToken.IsSymbol('(') or mToken.IsSymbol(';') or mToken.IsSymbol(':') then
    begin
      Break;
    end;
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, AMethod.MethodName) then
    begin
      AToken := mToken;
      Result := True;
    end;
  end;
end;

function TComponentModel.InsertAfterBegin(ABlock: TSyntaxNode; const AText: string; out AEdit: TRuleEdit): Boolean;
var
  mToken: TPascalToken;
  mIndent, mIndex: Integer;
begin
  Result := False;
  // Höchstens das Token am Blockanfang kommt in Frage: binär dorthin statt ab Dateianfang (#1342).
  mIndex := FContext.Tree.FirstTokenFrom(ABlock.StartOffset);
  if mIndex > High(FContext.Tree.Tokens) then
  begin
    Exit;
  end;
  mToken := FContext.Tree.Tokens[mIndex];
  if (mToken.Offset = ABlock.StartOffset) and mToken.IsKeyword('begin') then
  begin
    if ABlock.ChildCount > 0 then
    begin
      mIndent := ABlock[0].StartPos.Character;
    end
    else
    begin
      mIndent := mToken.StartPos.Character + 2;
    end;
    AEdit := TRuleEdit.Create(TTextRange.Create(mToken.EndPos, mToken.EndPos),
      FLineBreak + StringOfChar(' ', mIndent) + AText);
    Result := True;
  end;
end;

/// <summary>Erstes Token und letztes Token vor dem abschließenden end des Blocks (ohne Kommentare); False, wenn
/// der Block leer ist.</summary>
function TComponentModel.BlockTokens(ABlock: TSyntaxNode; out AFirst, ALast: TPascalToken): Boolean;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  Result := False;
  AFirst := Default(TPascalToken);
  ALast := Default(TPascalToken);
  mIndex := FContext.Tree.FirstTokenFrom(ABlock.StartOffset);
  while mIndex <= High(FContext.Tree.Tokens) do
  begin
    mToken := FContext.Tree.Tokens[mIndex];
    Inc(mIndex);
    if (mToken.Offset >= ABlock.EndOffset) or mToken.IsKeyword('end') and
      (mToken.Offset + Length(mToken.Text) = ABlock.EndOffset) then
    begin
      Break;
    end;
    if (mToken.Offset >= ABlock.StartOffset) and (mToken.Kind <> TPascalTokenKind.Comment) then
    begin
      if not Result then
      begin
        AFirst := mToken;
      end;
      ALast := mToken;
      Result := True;
    end;
  end;
end;

function TComponentModel.InsertBeforeEnd(ABlock: TSyntaxNode; const AText: string; out AEdit: TRuleEdit): Boolean;
var
  mFirst, mLast: TPascalToken;
  mIndent: Integer;
  mPrefix: string;
begin
  Result := BlockTokens(ABlock, mFirst, mLast);
  if not Result then
  begin
    Exit;
  end;
  if ABlock.ChildCount > 0 then
  begin
    mIndent := ABlock[0].StartPos.Character;
  end
  else
  begin
    mIndent := mFirst.StartPos.Character + 2;
  end;
  // Fehlt das Semikolon nach der letzten Anweisung, kommt es dazu.
  mPrefix := ';';
  if mLast.IsSymbol(';') or mLast.IsKeyword('begin') then
  begin
    mPrefix := '';
  end;
  AEdit := TRuleEdit.Create(TTextRange.Create(mLast.EndPos, mLast.EndPos),
    mPrefix + FLineBreak + StringOfChar(' ', mIndent) + AText);
end;
function PrepareModel(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
  out AModel: TComponentModel): Boolean;
var
  mContext: TRuleContext;
  mLocal: TUnitIndex;
begin
  AModel := nil;
  Result := AContext.Tree <> nil;
  if not Result then
  begin
    Exit;
  end;
  // const-Parameter dürfen anonyme Methoden nicht erfassen (E2555): lokale Kopien.
  mContext := AContext;
  mLocal := TRuleDerived.UnitIndex(ACache, AContext);
  AModel := TRuleDerived.Get<TComponentModel>(ACache, 'components.model',
    function: TComponentModel
    begin
      Result := TComponentModel.Create(mContext, mLocal);
    end);
end;

function DeclaredParent(const AClass: TClassInfo): string;
begin
  Result := '';
  if (AClass.Body.ChildCount > 0) and (AClass.Body[0].Kind = TSyntaxKind.TypeReference) then
  begin
    Result := AClass.Body[0].Name;
  end;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

function OwnFields(const AClass: TClassInfo): TArray<string>;
var
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  for mIndex := 0 to AClass.Body.ChildCount - 1 do
  begin
    if AClass.Body[mIndex].Kind = TSyntaxKind.Field then
    begin
      for mName in AClass.Body[mIndex].Name.Split([',']) do
      begin
        if Trim(mName) <> '' then
        begin
          Result := Result + [Trim(mName)];
        end;
      end;
    end;
  end;
end;

function SectionNames(ASection: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    for mName in ASection[mIndex].Name.Split([',']) do
    begin
      Result := Result + [Trim(mName)];
    end;
  end;
end;

function MethodLocalNames(const AMethod: TMethodImpl): TArray<string>;
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mHeader := AMethod.Decl.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader <> nil then
  begin
    Result := SectionNames(mHeader.FindChild(TSyntaxKind.Parameters));
  end;
  for mIndex := 0 to AMethod.Decl.ChildCount - 1 do
  begin
    if AMethod.Decl[mIndex].Kind = TSyntaxKind.VarSection then
    begin
      Result := Result + SectionNames(AMethod.Decl[mIndex]);
    end;
  end;
end;

end.
