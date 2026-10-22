unit Atlas.Common.Rules.Builtin.Forms;

// Regeln zum Lebenslauf von Formularen (Runde 67):
//   form-resource-missing   Neben der Unit liegt eine .dfm/.fmx, deren Wurzelklasse die Unit deklariert, aber
//                           kein {$R …} bindet eine Formulardatei ein: Create löst EResNotFound aus (#1054).
//                           Umgekehrt ein {$R *.dfm} bzw. {$R Name.dfm}, dessen Datei fehlt (wie F1026).
//                           Ein {$R} in einem beliebigen Zweig der bedingten Übersetzung zählt als eingebunden.
//                           Die Formulardatei kommt über TRuleContext.FormText, das Fehlen über ReadFile; ohne
//                           beides schweigt die Regel. Korrektur: {$R *.dfm} nach implementation.
//   form-autocreate-and-manual  Die .dpr erzeugt ein Formular mit Application.CreateForm, der Code weist der
//                           globalen Variablen zusätzlich TfrmX.Create(…) zu: zwei Instanzen (#1055). Die
//                           Variablen kommen über TRuleContext.AutoCreateForms. Still bei Prüfung der Variablen
//                           (Assigned, nil-Vergleich), vorheriger Freigabe (Free, FreeAndNil, Release), lokalen
//                           Namen und gleichnamigen Feldern der eigenen Klasse. Kennt die Regel die .dpr
//                           (ProjectMainSource, ReadFile), muss die Klasse zu CreateForm passen; Korrektur:
//                           die Zeile mit Application.CreateForm aus der .dpr entfernen.

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

  TFormAutoCreateAndManualRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
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
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
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

/// <summary>Deklariert die Routine AName selbst (Parameter, lokale Variable, Konstante)?</summary>
function DeclaresLocally(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
  Name: string;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[Index].Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter,
      TSyntaxKind.ConstDecl] then
      for Name in SplitString(ANode[Index].Name, ',') do
        if SameText(Trim(Name), AName) then
          Exit(True);
    if (ANode[Index].Kind <> TSyntaxKind.Block) and DeclaresLocally(ANode[Index], AName) then
      Exit(True);
  end;
  Result := False;
end;

/// <summary>Indizes der Code-Token (ohne Kommentare und Direktiven).</summary>
function CodeIndexes(const ATokens: TArray<TPascalToken>): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(ATokens) do
    if not (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Result := Result + [Index];
end;

function IntInArray(AValue: Integer; const AValues: TArray<Integer>): Boolean;
var
  Value: Integer;
begin
  for Value in AValues do
    if Value = AValue then
      Exit(True);
  Result := False;
end;

{ TFormAutoCreateAndManualRule }

type
  /// <summary>Application.CreateForm(TKlasse, Variable) einer .dpr mit Bereich der ganzen Zeile.</summary>
  TCreateFormCall = record
    TypeName: string;
    Variable: string;
    Statement: string;
    /// <summary>Von Zeilenanfang bis Anfang der nächsten Zeile, wenn die Anweisung allein steht, sonst nur
    /// die Anweisung mit Semikolon.</summary>
    Range: TTextRange;
  end;

function CreateFormCalls(const AMainSource: string): TArray<TCreateFormCall>;
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Position, Last: Integer;
  Call: TCreateFormCall;
  Lines: TArray<string>;
  Line: string;
  Alone: Boolean;

  function Text(APosition: Integer): string;
  begin
    Result := '';
    if APosition <= High(Code) then
      Result := Tokens[Code[APosition]].Text;
  end;

begin
  Result := nil;
  Tokens := TPascalLexer.Tokenize(AMainSource);
  Code := CodeIndexes(Tokens);
  Lines := TTextLines.SplitLines(AMainSource);
  for Position := 0 to High(Code) - 7 do
    if SameText(Text(Position), 'Application') and (Text(Position + 1) = '.') and
      SameText(Text(Position + 2), 'CreateForm') and (Text(Position + 3) = '(') and (Text(Position + 5) = ',') and
      (Text(Position + 7) = ')') and (Tokens[Code[Position + 6]].Kind = TPascalTokenKind.Identifier) then
    begin
      Call := Default(TCreateFormCall);
      Call.TypeName := Text(Position + 4);
      Call.Variable := Text(Position + 6);
      Last := Position + 7;
      if Text(Position + 8) = ';' then
        Last := Position + 8;
      Call.Statement := 'Application.CreateForm(' + Call.TypeName + ', ' + Call.Variable + ')';
      Call.Range := TTextRange.Create(Tokens[Code[Position]].StartPos, Tokens[Code[Last]].EndPos);
      Alone := Call.Range.StartPos.Line = Call.Range.EndPos.Line;
      if Alone and (Call.Range.StartPos.Line <= High(Lines)) then
      begin
        Line := Lines[Call.Range.StartPos.Line];
        Alone := (Trim(Copy(Line, 1, Call.Range.StartPos.Character)) = '') and
          (Trim(Copy(Line, Call.Range.EndPos.Character + 1, MaxInt)) = '');
      end;
      if Alone and (Call.Range.StartPos.Line < High(Lines)) then
        Call.Range := TTextRange.Create(Call.Range.StartPos.Line, 0, Call.Range.StartPos.Line + 1, 0);
      Result := Result + [Call];
    end;
end;

function TFormAutoCreateAndManualRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-autocreate-and-manual', TRuleSeverity.Warning,
    'Formular automatisch und zusätzlich von Hand erzeugt');
end;

procedure TFormAutoCreateAndManualRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Calls: TArray<TCreateFormCall>;
  Local: TUnitIndex;
  MainName: string;
  Reported: TArray<Integer>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  function CodeAt(AOffset: Integer): Integer;
  begin
    for Result := 0 to High(Code) do
      if Token(Result).Offset >= AOffset then
        Exit;
    Result := Length(Code);
  end;

  function FindCall(const AVariable: string; out ACall: TCreateFormCall): Boolean;
  var
    Call: TCreateFormCall;
  begin
    for Call in Calls do
      if SameText(Call.Variable, AVariable) then
      begin
        ACall := Call;
        Exit(True);
      end;
    Result := False;
  end;

  // Feld oder Property gleichen Namens in der Klasse der Methode (verdeckt die globale Variable).
  function IsMember(ARoutine: TSyntaxNode; const AName: string): Boolean;
  var
    Symbol: TIndexSymbol;
    Owner: string;
  begin
    Result := False;
    if LastDelimiter('.', ARoutine.Name) = 0 then
      Exit;
    Owner := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    for Symbol in Local.Symbols do
      if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and SameText(Symbol.Name, AName) and
        SameText(Symbol.Container, Owner) then
        Exit(True);
  end;

  // Prüft oder gibt die Routine die Variable frei (Assigned, nil-Vergleich, Free, FreeAndNil, Release)?
  function Handled(AFirst, ALast: Integer; const AName: string): Boolean;
  var
    Position: Integer;
  begin
    for Position := AFirst to ALast do
      if IsName(Position, AName) and not IsSym(Position - 1, '.') then
        if (IsSym(Position - 1, '(') and (IsName(Position - 2, 'Assigned') or IsName(Position - 2, 'FreeAndNil'))) or
          ((IsSym(Position + 1, '<>') or IsSym(Position + 1, '=')) and (Position + 2 <= High(Code)) and
          Token(Position + 2).IsKeyword('nil')) or
          (IsSym(Position + 1, '.') and (IsName(Position + 2, 'Free') or IsName(Position + 2, 'Release') or
          IsName(Position + 2, 'DisposeOf'))) then
          Exit(True);
    Result := False;
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Body: TSyntaxNode;
    First, Last, Position: Integer;
    Name, TypeName: string;
    Call: TCreateFormCall;
    HasCall: Boolean;
    Fixes: TArray<TRuleFix>;
  begin
    Body := TRoutineBody.BodyOf(ARoutine);
    if Body = nil then
      Exit;
    First := CodeAt(Body.StartOffset);
    Last := CodeAt(Body.EndOffset) - 1;
    // V := TKlasse.Create(…)
    for Position := First to Last - 4 do
    begin
      if (Token(Position).Kind <> TPascalTokenKind.Identifier) or IsSym(Position - 1, '.') or
        not IsSym(Position + 1, ':=') or (Token(Position + 2).Kind <> TPascalTokenKind.Identifier) or
        not IsSym(Position + 3, '.') or not IsName(Position + 4, 'Create') then
        Continue;
      // Verschachtelte Routinen liegen im Rumpf der äußeren: jede Stelle einmal.
      if IntInArray(Position, Reported) then
        Continue;
      Name := Token(Position).Text;
      TypeName := Token(Position + 2).Text;
      if not MatchText(Name, AContext.AutoCreateForms) then
        Continue;
      HasCall := FindCall(Name, Call);
      if HasCall and not SameText(Call.TypeName, TypeName) then
        Continue;
      if DeclaresLocally(ARoutine, Name) or IsMember(ARoutine, Name) or Handled(First, Last, Name) then
        Continue;
      Reported := Reported + [Position];
      Fixes := nil;
      if HasCall then
      begin
        Fixes := [TRuleFix.Create(Call.Statement + ' aus ' + MainName + ' entfernen',
          [TRuleEdit.Create(Call.Range, '')])];
        Fixes[0].FileName := AContext.ProjectMainSource;
      end;
      AReport.Add(TTextRange.Create(Token(Position).StartPos, Token(Position + 4).EndPos),
        Format('%s wird schon in %s erzeugt; hier entsteht eine zweite Instanz.', [Name, MainName]),
        TRuleConfidence.High, Fixes);
    end;
  end;

var
  Data: TBytes;
  Format_: TFileFormat;
  Routine: TSyntaxNode;
  Cache: IRuleDerivedCache;
begin
  if (Length(AContext.AutoCreateForms) = 0) or (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    (AContext.Tree.Root.Kind = TSyntaxKind.ProgramFile) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := CodeIndexes(Tokens);
  Calls := nil;
  MainName := 'der .dpr';
  if AContext.ProjectName <> '' then
    MainName := AContext.ProjectName + '.dpr';
  if AContext.ProjectMainSource <> '' then
  begin
    MainName := ExtractFileName(AContext.ProjectMainSource);
    if Assigned(AContext.ReadFile) and AContext.ReadFile(AContext.ProjectMainSource, Data) then
      Calls := CreateFormCalls(TFileEncoding.Decode(Data, Format_));
  end;
  Cache := TRuleDerived.Open(AContext);
  Local := TRuleDerived.UnitIndex(Cache, AContext);
  Reported := nil;
  for Routine in TRuleDerived.Routines(Cache, AContext) do
    CheckRoutine(Routine);
end;

procedure RegisterFormRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFormResourceMissingRule.Create);
  ARegistry.Register(TFormAutoCreateAndManualRule.Create);
end;

end.
