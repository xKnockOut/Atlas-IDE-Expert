unit Atlas.Common.Rules.Builtin.Forms;

// Regeln zum Lebenslauf von Formularen (Runde 67):
//   form-resource-missing   Neben der Unit liegt eine .dfm/.fmx, deren Wurzelklasse die Unit deklariert, aber
//                           kein {$R …} bindet eine Formulardatei ein: Create löst EResNotFound aus (#1054).
//                           Umgekehrt ein {$R *.dfm} bzw. {$R Name.dfm}, dessen Datei fehlt (wie F1026).
//                           Ein {$R} in einem beliebigen Zweig der bedingten Übersetzung zählt als eingebunden.
//                           Die Formulardatei kommt über TRuleContext.FormText, das Fehlen über ReadFile; ohne
//                           beides schweigt die Regel. Korrektur: {$R *.dfm} nach implementation.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TFormResourceMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Formulardatei aus {$R …} bzw. {$RESOURCE …} (.dfm, .fmx), * durch AUnitFile ersetzt; False
    /// bei anderen Ressourcen und bei * ohne AUnitFile.</summary>
    class function FormResource(const ADirective, AUnitFile: string; out AFileName: string): Boolean; static;
  end;

procedure RegisterFormRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Text.Lines;

/// <summary>Klasse ATypeName der Unit (Interface oder Implementation), sonst nil.</summary>
function FindClassDecl(ANode: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, ATypeName) then
    Exit(ANode.FindChild(TSyntaxKind.ClassType));
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode.Children[Index].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.InterfaceSection,
      TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
    begin
      Result := FindClassDecl(ANode.Children[Index], ATypeName);
      if Result <> nil then
        Exit;
    end;
  Result := nil;
end;

/// <summary>Klassenname des Wurzelobjekts der Formulardatei; '' ohne lesbares Wurzelobjekt.</summary>
function FormClassName(const AFormText: string): string;
var
  Document: TDfmDocument;
begin
  Result := '';
  if AFormText = '' then
    Exit;
  Document := TDfmParser.Parse(AFormText);
  try
    if Document.Root <> nil then
      Result := Document.Root.TypeName;
  finally
    Document.Free;
  end;
end;

/// <summary>Dateiname der Unit ohne Endung aus FileName bzw. RelativePath; '' wenn unbekannt.</summary>
function UnitFileBase(const AContext: TRuleContext): string;
var
  Path: string;
begin
  Path := AContext.FileName;
  if Path = '' then
    Path := AContext.RelativePath;
  Result := ChangeFileExt(ExtractFileName(StringReplace(Path, '/', '\', [rfReplaceAll])), '');
  if Result = '' then
    Result := AContext.UnitName;
end;

{ TFormResourceMissingRule }

function TFormResourceMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-resource-missing', TRuleSeverity.Error,
    'Formular-Unit ohne {$R *.dfm} bzw. {$R} ohne Formulardatei');
end;

class function TFormResourceMissingRule.FormResource(const ADirective, AUnitFile: string;
  out AFileName: string): Boolean;
var
  Text: string;
begin
  Result := False;
  Text := Trim(ADirective);
  if not (StartsText('{$R ', Text) or StartsText('{$RESOURCE ', Text)) or not EndsText('}', Text) then
    Exit;
  Text := Trim(Copy(Text, Pos(' ', Text) + 1, Length(Text) - Pos(' ', Text) - 1));
  // {$R 'a.dfm'} bzw. {$R *.Windows.fmx MSWINDOWS}: nur die erste Angabe.
  if StartsText('''', Text) then
    Text := Copy(Text, 2, Pos('''', Copy(Text, 2, MaxInt)) - 1)
  else if Pos(' ', Text) > 0 then
    Text := Copy(Text, 1, Pos(' ', Text) - 1);
  if not (EndsText('.dfm', Text) or EndsText('.fmx', Text)) then
    Exit;
  if StartsText('*', Text) then
  begin
    if AUnitFile = '' then
      Exit;
    Text := AUnitFile + Copy(Text, 2, MaxInt);
  end;
  AFileName := Text;
  Result := True;
end;

procedure TFormResourceMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Token, Implementation_: TPascalToken;
  HasImplementation, Included: Boolean;
  UnitFile, FileName, ClassName, Extension, FormName, LineBreak: string;
  Data: TBytes;
  Fix: TRuleFix;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Tree.Root.Kind <> TSyntaxKind.UnitFile) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  UnitFile := UnitFileBase(AContext);
  HasImplementation := False;
  Implementation_ := Default(TPascalToken);
  Included := False;
  for Token in Tokens do
    if (Token.Kind = TPascalTokenKind.Keyword) and Token.IsKeyword('implementation') and not HasImplementation then
    begin
      HasImplementation := True;
      Implementation_ := Token;
    end
    else if (Token.Kind = TPascalTokenKind.Directive) and FormResource(Token.Text, UnitFile, FileName) then
    begin
      Included := True;
      // Eingebundene Datei fehlt neben der Unit (wie F1026).
      if Assigned(AContext.ReadFile) and not AContext.ReadFile(FileName, Data) then
        AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos),
          Format('%s fehlt; der Compiler bricht mit F1026 ab.', [ExtractFileName(FileName)]));
    end;
  if Included or not HasImplementation then
    Exit;
  ClassName := FormClassName(AContext.FormText);
  if (ClassName = '') or (FindClassDecl(AContext.Tree.Root, ClassName) = nil) then
    Exit;
  Extension := '.dfm';
  if SameText(ExtractFileExt(AContext.FormFile), '.fmx') then
    Extension := '.fmx';
  FormName := UnitFile;
  if AContext.FormFile <> '' then
    FormName := ChangeFileExt(ExtractFileName(AContext.FormFile), '');
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Fix := TRuleFix.Create('{$R *' + Extension + '} nach implementation einfügen',
    [TRuleEdit.Create(TTextRange.Create(Implementation_.EndPos, Implementation_.EndPos),
    LineBreak + LineBreak + '{$R *' + Extension + '}')], True);
  AReport.Add(TTextRange.Create(Implementation_.StartPos, Implementation_.EndPos),
    Format('%s wird nicht eingebunden; %s.Create löst EResNotFound aus.', [FormName + Extension,
    ClassName]), TRuleConfidence.High, [Fix]);
end;

procedure RegisterFormRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFormResourceMissingRule.Create);
end;

end.
