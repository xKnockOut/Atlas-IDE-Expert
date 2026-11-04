unit Atlas.Common.Rules.Builtin.FormReferences;

// Verweise der Formulardatei auf andere Module (Marco, 03.11.2026):
//   dfm-reference-unit-missing  Eine Property der Formulardatei zeigt auf eine Komponente eines anderen
//                           Formulars, Rahmens oder Datenmoduls (Connection = Form1.Connection), dessen Unit
//                           weder im interface- noch im implementation-uses steht. Die IDE öffnet beim Laden
//                           des Formulars nur Module aus den uses mit; sonst bleibt der Verweis leer und geht
//                           beim Speichern verloren, zur Laufzeit löst die VCL ihn nur auf, solange das Modul
//                           existiert.
//
// Das Modul ist der Name der Wurzelkomponente (Form1, nicht TForm1). Seine Unit kommt aus der .dpr des
// Projekts (Unit1 in 'Unit1.pas' {Form1}, Sicherheit hoch), sonst aus dem Index: globale Variable dieses
// Namens im interface einer Unit, deren Typ dieselbe Unit als Klasse deklariert (Sicherheit mittel).
// Still bei Verweisen auf das eigene Formular, auf eigene Komponenten (eingebettete Rahmen: Frame11.Button1)
// und auf Module, deren Unit weder .dpr noch Index kennen. Gemeldet wird in der Unit am Feld der
// Komponente, die den Verweis hält, sonst an der Formularklasse; die Zeile der Formulardatei steht als
// weitere Stelle dabei. Korrektur: die Unit ins implementation-uses aufnehmen, wie es die IDE anbietet.
// Angemeldet wird die Regel mit den übrigen Formularregeln in RegisterFormRules (Builtin.Forms).

interface

uses
  Atlas.Common.Rules.Contract;

const
  cDfmReferenceUnitMissingRuleId = 'dfm-reference-unit-missing';

type
  /// <summary>Modul (Name der Wurzelkomponente) eines Projekts mit seiner Unit.</summary>
  TFormModuleUnit = record
    ModuleName: string;
    UnitName: string;
  end;

  TDfmReferenceUnitMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Module aus den uses einer .dpr: Kommentar hinter "in '…'" wie {Form1} oder
    /// {DM: TDataModule}, dazu der Unit-Name vor in.</summary>
    class function ProjectModules(const AMainSource: string): TArray<TFormModuleUnit>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Derived,
  Atlas.Text.Lines;

type
  /// <summary>Ein Lauf der Regel über eine Formulardatei.</summary>
  TFormReferenceCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FModel: TFormModel;
    FUnitIndex: TUnitIndex;
    FProjectModules: TArray<TFormModuleUnit>;
    FProjectRead: Boolean;
    function ProjectUnit(const AModuleName: string; out AUnitName: string): Boolean;
    function IndexUnit(const AModuleName: string; out AUnitName: string): Boolean;
    function IsUsed(const AUnitName: string): Boolean;
    function ClassRange: TTextRange;
    function ReportRange(const AReference: TFormModuleReference): TTextRange;
    function Fixes(const AUnitName: string): TArray<TRuleFix>;
    procedure Report(const AReference: TFormModuleReference; const AUnitName: string;
      AConfidence: TRuleConfidence);
    procedure CheckReference(const AReference: TFormModuleReference);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

/// <summary>Name des Moduls aus einem Kommentar der .dpr: {Form1} bzw. {DM: TDataModule}; '' ohne.</summary>
function CommentModule(const AComment: string): string;
var
  mEnd: Integer;
begin
  Result := '';
  if not AComment.StartsWith('{') then
  begin
    Exit;
  end;
  mEnd := Pos(':', AComment);
  if mEnd = 0 then
  begin
    mEnd := Length(AComment);
  end;
  Result := Trim(Copy(AComment, 2, mEnd - 2));
end;

/// <summary>Unit-Name mit Punkten, der mit dem Bezeichner an ALast endet (Projekt.Formulare.Kunde).</summary>
function DottedNameBefore(const ATokens: TArray<TPascalToken>; ALast: Integer): string;
var
  mIndex: Integer;
begin
  Result := ATokens[ALast].Text;
  mIndex := ALast;
  while (mIndex >= 2) and ATokens[mIndex - 1].IsSymbol('.') and
    (ATokens[mIndex - 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := ATokens[mIndex - 2].Text + '.' + Result;
    Dec(mIndex, 2);
  end;
end;

/// <summary>Steht an AIndex der Dateiname eines Eintrags "Unit in '…' {Modul}"?</summary>
function IsModuleEntry(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 2) and (AIndex < High(ATokens)) and
    (ATokens[AIndex].Kind = TPascalTokenKind.StringLiteral) and ATokens[AIndex - 1].IsKeyword('in') and
    (ATokens[AIndex - 2].Kind = TPascalTokenKind.Identifier) and
    (ATokens[AIndex + 1].Kind = TPascalTokenKind.Comment);
end;

{ TDfmReferenceUnitMissingRule }

function TDfmReferenceUnitMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDfmReferenceUnitMissingRuleId, TRuleSeverity.Warning,
    'Formulardatei verweist auf ein Modul, dessen Unit nicht in den uses steht');
end;

class function TDfmReferenceUnitMissingRule.ProjectModules(const AMainSource: string): TArray<TFormModuleUnit>;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mModule: TFormModuleUnit;
begin
  Result := nil;
  mTokens := TPascalLexer.Tokenize(AMainSource);
  for mIndex := 0 to High(mTokens) do
  begin
    if IsModuleEntry(mTokens, mIndex) then
    begin
      mModule.ModuleName := CommentModule(mTokens[mIndex + 1].Text);
      mModule.UnitName := DottedNameBefore(mTokens, mIndex - 2);
      if mModule.ModuleName <> '' then
      begin
        Result := Result + [mModule];
      end;
    end;
  end;
end;

procedure TDfmReferenceUnitMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TFormReferenceCheck;
begin
  if (AContext.FormText = '') or (AContext.Tree = nil) then
  begin
    Exit;
  end;
  mCheck := TFormReferenceCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ TFormReferenceCheck }

constructor TFormReferenceCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FModel := TFormModel.Create(AContext.FormText);
  FUnitIndex := TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext);
end;

destructor TFormReferenceCheck.Destroy;
begin
  FModel.Free;
  inherited;
end;

procedure TFormReferenceCheck.Run;
var
  mReference: TFormModuleReference;
begin
  if (FModel.Document.Root = nil) or (FModel.FormClass = '') then
  begin
    Exit;
  end;
  for mReference in FModel.References do
  begin
    CheckReference(mReference);
  end;
end;

procedure TFormReferenceCheck.CheckReference(const AReference: TFormModuleReference);
var
  mUnitName: string;
begin
  // Das eigene Formular oder eine eigene Komponente (eingebetteter Rahmen Frame11.Button1).
  if FModel.IsOwnName(AReference.ModuleName) then
  begin
    Exit;
  end;
  if ProjectUnit(AReference.ModuleName, mUnitName) then
  begin
    Report(AReference, mUnitName, TRuleConfidence.High);
  end
  else if IndexUnit(AReference.ModuleName, mUnitName) then
  begin
    Report(AReference, mUnitName, TRuleConfidence.Medium);
  end;
end;

function TFormReferenceCheck.ProjectUnit(const AModuleName: string; out AUnitName: string): Boolean;
var
  mData: TBytes;
  mFormat: TFileFormat;
  mModule: TFormModuleUnit;
begin
  if not FProjectRead then
  begin
    FProjectRead := True;
    if (FContext.ProjectMainSource <> '') and Assigned(FContext.ReadFile) and
      FContext.ReadFile(FContext.ProjectMainSource, mData) then
    begin
      FProjectModules := TDfmReferenceUnitMissingRule.ProjectModules(TFileEncoding.Decode(mData, mFormat));
    end;
  end;
  Result := False;
  for mModule in FProjectModules do
  begin
    if SameText(mModule.ModuleName, AModuleName) then
    begin
      AUnitName := mModule.UnitName;
      Exit(True);
    end;
  end;
end;

function TFormReferenceCheck.IndexUnit(const AModuleName: string; out AUnitName: string): Boolean;
var
  mVariable, mClass: TSymbolLocation;
begin
  Result := False;
  if FContext.Index = nil then
  begin
    Exit;
  end;
  // Form1: TForm1 im interface einer Unit, die TForm1 selbst deklariert.
  for mVariable in FContext.Index.FindSymbols(AModuleName) do
  begin
    if (mVariable.Symbol.Kind = TIndexSymbolKind.Variable) and (mVariable.Symbol.Container = '') and
      mVariable.Symbol.InInterface and (mVariable.Symbol.TypeName <> '') then
    begin
      for mClass in FContext.Index.FindSymbols(mVariable.Symbol.TypeName) do
      begin
        if (mClass.Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(mClass.UnitName, mVariable.UnitName) then
        begin
          AUnitName := mVariable.UnitName;
          Exit(True);
        end;
      end;
    end;
  end;
end;

function TFormReferenceCheck.IsUsed(const AUnitName: string): Boolean;
var
  mUsed: TArray<string>;
begin
  mUsed := FUnitIndex.InterfaceUses + FUnitIndex.ImplementationUses;
  Result := SameText(AUnitName, FContext.UnitName) or TUsesClauses.IsUsed(mUsed, AUnitName, FContext.Namespaces);
end;

function TFormReferenceCheck.ClassRange: TTextRange;
var
  mSymbol: TIndexSymbol;
begin
  Result := Default(TTextRange);
  for mSymbol in FUnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and (mSymbol.Container = '') and
      SameText(mSymbol.Name, FModel.FormClass) then
    begin
      Exit(mSymbol.SelectionRange);
    end;
  end;
end;

function TFormReferenceCheck.ReportRange(const AReference: TFormModuleReference): TTextRange;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FUnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, FModel.FormClass) and
      SameText(mSymbol.Name, AReference.Obj.Name) then
    begin
      Exit(mSymbol.SelectionRange);
    end;
  end;
  Result := ClassRange;
end;

function TFormReferenceCheck.Fixes(const AUnitName: string): TArray<TRuleFix>;
var
  mEdit: TTextEdit;
begin
  Result := nil;
  // MaxInt: Abschnitt implementation, wie die IDE den Eintrag anlegt.
  if TUsesClauses.AddUnit(FContext.Tree.Tokens, MaxInt, AUnitName, TTextLines.LineBreakOf(FContext.Text),
    mEdit) then
  begin
    Result := [TRuleFix.Create(Format('uses %s ergänzen', [AUnitName]), [mEdit])];
  end;
end;

procedure TFormReferenceCheck.Report(const AReference: TFormModuleReference; const AUnitName: string;
  AConfidence: TRuleConfidence);
var
  mMessage, mDetails: string;
  mRelated: TRuleRelated;
  mExtended: IRuleRelatedReport;
begin
  if IsUsed(AUnitName) then
  begin
    Exit;
  end;
  mMessage := Format('%s = %s: %s stammt aus %s, die Unit steht nicht in den uses. Die IDE öffnet %s dann ' +
    'nicht mit, der Verweis bleibt leer und geht beim Speichern verloren.', [AReference.Reference.Name,
    AReference.Reference.Value, AReference.ModuleName, AUnitName, AReference.ModuleName]);
  mDetails := Format('Zur Laufzeit löst die VCL den Verweis nur auf, solange ein Modul %s existiert.',
    [AReference.ModuleName]);
  // Weitere Stellen tragen nur Treffer mit hoher Sicherheit (AddRelated kennt keine andere).
  if (AConfidence = TRuleConfidence.High) and (FContext.FormFile <> '') and
    Supports(FReport, IRuleRelatedReport, mExtended) then
  begin
    mRelated.FileName := FContext.FormFile;
    mRelated.Range := AReference.Reference.ValueRange;
    mRelated.Message := Format('Verweis auf %s', [AReference.Reference.Value]);
    mExtended.AddRelated(ReportRange(AReference), mMessage, mDetails, TRuleSeverity.Default,
      Fixes(AUnitName), [mRelated]);
  end
  else
  begin
    FReport.AddWithDetails(ReportRange(AReference), mMessage, mDetails, AConfidence, Fixes(AUnitName));
  end;
end;

end.
