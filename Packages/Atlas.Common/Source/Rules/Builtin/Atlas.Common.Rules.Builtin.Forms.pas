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
//   inherited-form-handler-without-inherited  Geerbtes Formular (inherited in der Formulardatei): Ein Vorfahr
//                           belegt dasselbe Ereignis derselben Komponente mit einem gleichnamigen Handler, der
//                           Handler des Nachfahren ruft inherited aber nicht auf (#1056). Die Formulardateien der
//                           Vorfahren kommen über den Index (Datei der Klasse) bzw. die Units der uses-Liste neben
//                           der Unit (ReadFile); die Kette folgt inherited-Wurzeln bis zu einer object-Wurzel.
//                           Andere Handlernamen gelten als bewusster Ersatz. Korrektur: inherited; nach begin.
//   self-free-in-event-handler  Free, Destroy, DisposeOf oder FreeAndNil auf Self bzw. auf die globale Variable der
//                           eigenen Formularklasse als Anweisung in einem Ereignis-Handler des Formulars (#1057):
//                           Nach der Rückkehr greift die VCL noch auf das Objekt zu. Handler sind die Methoden
//                           aus der Formulardatei und Methoden mit Sender: TObject; Formular heißt Wurzelklasse
//                           der Formulardatei mit ClientWidth/ClientHeight bzw. Vorfahr TForm/TCustomForm (Rahmen
//                           und Datenmodule haben kein Release). Anweisungen in anonymen Methoden und with-Blöcken
//                           zählen nicht. Korrektur: Release, in OnClose (var Action: TCloseAction) Action := caFree.

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

  TInheritedFormHandlerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSelfFreeInEventHandlerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterFormRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.Editing.UsesClause,
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

/// <summary>Klasse ATypeName der Unit (Interface oder Implementation), sonst nil. Iterativ (Bericht M1).
/// </summary>
function FindClassDecl(ANode: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, ATypeName) then
      begin
        Result := Node.FindChild(TSyntaxKind.ClassType);
        if Result <> nil then
          Exit;
        Continue;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
        if Node.Children[Index].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.InterfaceSection,
          TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
          Pending.Push(Node.Children[Index]);
    end;
  finally
    Pending.Free;
  end;
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

/// <summary>Deklariert die Routine AName selbst (Parameter, lokale Variable, Konstante)? Iterativ
/// (Bericht M1).</summary>
function DeclaresLocally(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node, Child: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      for Index := 0 to Node.ChildCount - 1 do
      begin
        Child := Node[Index];
        if Child.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter,
          TSyntaxKind.ConstDecl] then
          for Name in SplitString(Child.Name, ',') do
            if SameText(Trim(Name), AName) then
              Exit(True);
      end;
      for Index := Node.ChildCount - 1 downto 0 do
        if Node[Index].Kind <> TSyntaxKind.Block then
          Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
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
  var
    mHigh, mMiddle: Integer;
  begin
    // Binär statt ab Dateianfang mit einer Kopie je Token: Code steht nach Offset sortiert (#1342).
    Result := 0;
    mHigh := Length(Code);
    while Result < mHigh do
    begin
      mMiddle := (Result + mHigh) div 2;
      if Tokens[Code[mMiddle]].Offset < AOffset then
        Result := mMiddle + 1
      else
        mHigh := mMiddle;
    end;
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

{ TInheritedFormHandlerRule }

type
  /// <summary>Ereignis einer Komponente der Formulardatei; Component '' = das Formular selbst.</summary>
  TFormEvent = record
    Component: string;
    Event: string;
    Handler: string;
    /// <summary>Klasse, deren Formulardatei den Handler setzt (bei Vorfahren).</summary>
    Owner: string;
  end;

procedure CollectEvents(AObject: TDfmObject; AIsRoot: Boolean; const AOwner: string;
  var AEvents: TArray<TFormEvent>);
var
  Prop: TDfmProperty;
  Child: TDfmObject;
  Event: TFormEvent;
begin
  if AObject.Kind = TDfmObjectKind.Item then
    Exit;
  for Prop in AObject.Properties do
    if Prop.IsEvent then
    begin
      Event := Default(TFormEvent);
      if not AIsRoot then
        Event.Component := AObject.Name;
      Event.Event := Prop.Name;
      Event.Handler := Prop.Value;
      Event.Owner := AOwner;
      AEvents := AEvents + [Event];
    end;
  for Child in AObject.Children do
    CollectEvents(Child, False, AOwner, AEvents);
end;

function TInheritedFormHandlerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-form-handler-without-inherited', TRuleSeverity.Warning,
    'Ereignis-Handler im geerbten Formular ohne inherited');
end;

procedure TInheritedFormHandlerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Document: TDfmDocument;
  Own, Inherited_: TArray<TFormEvent>;
  UsedUnits: TArray<string>;

  // Formulardatei der Klasse AClassName: über den Index, sonst über die Units AUnits neben der Unit.
  function AncestorForm(const AClassName: string; const AUnits: TArray<string>; out AText, AFileName: string):
    Boolean;
  var
    Location: TSymbolLocation;
    Candidates: TArray<string>;
    Candidate, Extension, Name: string;
    Data: TBytes;
    Format_: TFileFormat;
    Parsed: TDfmDocument;
  begin
    Result := False;
    if not Assigned(AContext.ReadFile) then
      Exit;
    Name := Copy(AClassName, LastDelimiter('.', AClassName) + 1, MaxInt);
    Candidates := nil;
    if AContext.Index <> nil then
      for Location in AContext.Index.FindSymbols(Name) do
        if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
          Candidates := Candidates + [ChangeFileExt(Location.FileName, '')];
    for Candidate in AUnits do
      Candidates := Candidates + [Candidate];
    for Candidate in Candidates do
      for Extension in TArray<string>.Create('.dfm', '.fmx') do
        if AContext.ReadFile(Candidate + Extension, Data) then
        begin
          AText := TFileEncoding.Decode(Data, Format_);
          Parsed := TDfmParser.Parse(AText);
          try
            if (Parsed.Root <> nil) and SameText(Parsed.Root.TypeName, Name) then
            begin
              AFileName := Candidate + Extension;
              Exit(True);
            end;
          finally
            Parsed.Free;
          end;
        end;
  end;

  // Vorfahr von AClassName aus dem Quelltext der Unit neben AFormFile ('' ohne).
  function ParentInFile(const AClassName, AFormFile: string; out AUnits: TArray<string>): string;
  var
    Data: TBytes;
    Format_: TFileFormat;
    Text: string;
    Match: TMatch;
  begin
    Result := '';
    AUnits := nil;
    if not AContext.ReadFile(ChangeFileExt(AFormFile, '.pas'), Data) then
      Exit;
    Text := TFileEncoding.Decode(Data, Format_);
    AUnits := TUsesClauses.UsedUnits(TPascalLexer.Tokenize(Text));
    Match := TRegEx.Match(Text, '\b' + AClassName + '\s*=\s*class\s*\(\s*([\w.]+)', [roIgnoreCase]);
    if Match.Success then
      Result := Match.Groups[1].Value;
  end;

  function FindInherited(const AEvent: TFormEvent; out AFound: TFormEvent): Boolean;
  var
    Event: TFormEvent;
  begin
    for Event in Inherited_ do
      if SameText(Event.Component, AEvent.Component) and SameText(Event.Event, AEvent.Event) then
      begin
        AFound := Event;
        Exit(True);
      end;
    Result := False;
  end;

  procedure CollectAncestors(const AClassName: string);
  var
    Parent, Text, FileName: string;
    Units, More: TArray<string>;
    Level: Integer;
    Parsed: TDfmDocument;
    IsInherited: Boolean;
    Events: TArray<TFormEvent>;
    Event, Found: TFormEvent;
  begin
    Parent := AClassName;
    Units := UsedUnits;
    for Level := 1 to 8 do
    begin
      if not AncestorForm(Parent, Units, Text, FileName) then
        Exit;
      Parsed := TDfmParser.Parse(Text);
      try
        Events := nil;
        CollectEvents(Parsed.Root, True, Parsed.Root.TypeName, Events);
        IsInherited := Parsed.Root.Kind = TDfmObjectKind.Inherited_;
      finally
        Parsed.Free;
      end;
      // Der nächste Vorfahr gewinnt.
      for Event in Events do
        if not FindInherited(Event, Found) then
          Inherited_ := Inherited_ + [Event];
      if not IsInherited then
        Exit;
      Parent := ParentInFile(Copy(Parent, LastDelimiter('.', Parent) + 1, MaxInt), FileName, More);
      if Parent = '' then
        Exit;
      Units := Units + More;
    end;
  end;

  function FindRoutine(const AName: string): TSyntaxNode;
  var
    Routine: TSyntaxNode;
  begin
    for Routine in TRuleDerived.Routines(TRuleDerived.Open(AContext), AContext) do
      if SameText(Routine.Name, AName) then
        Exit(Routine);
    Result := nil;
  end;

var
  ClassNode, Routine, Body: TSyntaxNode;
  Parent, ClassName, LineBreak: string;
  Event, Ancestor: TFormEvent;
  Token, NameToken, BeginToken: TPascalToken;
  mIndex: Integer;
  HasInherited, HasName, HasBegin: Boolean;
  Fixes: TArray<TRuleFix>;
begin
  if (AContext.FormText = '') or (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not ContainsText(AContext.FormText, 'inherited') then
    Exit;
  Document := TDfmParser.Parse(AContext.FormText);
  try
    if (Document.Root = nil) or (Document.Root.Kind <> TDfmObjectKind.Inherited_) then
      Exit;
    ClassName := Document.Root.TypeName;
    Own := nil;
    CollectEvents(Document.Root, True, ClassName, Own);
  finally
    Document.Free;
  end;
  if Length(Own) = 0 then
    Exit;
  ClassNode := FindClassDecl(AContext.Tree.Root, ClassName);
  if (ClassNode = nil) or (ClassNode.ChildCount = 0) or (ClassNode[0].Kind <> TSyntaxKind.TypeReference) then
    Exit;
  Parent := ClassNode[0].Name;
  UsedUnits := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  Inherited_ := nil;
  CollectAncestors(Parent);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  for Event in Own do
  begin
    // Nur gleichnamige Handler: ein anderer Name ersetzt den Handler des Vorfahren bewusst.
    if not FindInherited(Event, Ancestor) or not SameText(Ancestor.Handler, Event.Handler) then
      Continue;
    Routine := FindRoutine(ClassName + '.' + Event.Handler);
    if Routine = nil then
      Continue;
    Body := TRoutineBody.BodyOf(Routine);
    if Body = nil then
      Continue;
    HasInherited := False;
    HasName := False;
    HasBegin := False;
    NameToken := Default(TPascalToken);
    BeginToken := Default(TPascalToken);
    for mIndex := AContext.Tree.FirstTokenFrom(Routine.StartOffset) to High(AContext.Tree.Tokens) do
    begin
      Token := AContext.Tree.Tokens[mIndex];
      if (Token.Offset < Routine.StartOffset) or (Token.Offset >= Routine.EndOffset) or
        (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
        Continue;
      if not HasName and (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, Event.Handler) then
      begin
        HasName := True;
        NameToken := Token;
      end;
      if not HasBegin and (Token.Offset >= Body.StartOffset) and Token.IsKeyword('begin') then
      begin
        HasBegin := True;
        BeginToken := Token;
      end;
      if (Token.Offset >= Body.StartOffset) and Token.IsKeyword('inherited') then
        HasInherited := True;
    end;
    if HasInherited or not HasName then
      Continue;
    Fixes := nil;
    if HasBegin then
      Fixes := [TRuleFix.Create('inherited; am Anfang einfügen', [TRuleEdit.Create(TTextRange.Create(
        BeginToken.EndPos, BeginToken.EndPos), LineBreak + TTextLines.IndentOf(AContext.Text, BeginToken.StartPos.Line) +
        '  inherited;')], True)];
    AReport.Add(TTextRange.Create(NameToken.StartPos, NameToken.EndPos),
      Format('%s.%s wird nicht mehr ausgeführt (kein inherited).', [Ancestor.Owner, Ancestor.Handler]),
      TRuleConfidence.High, Fixes);
  end;
end;

{ TSelfFreeInEventHandlerRule }

function TSelfFreeInEventHandlerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('self-free-in-event-handler', TRuleSeverity.Error,
    'Formular gibt sich im eigenen Ereignis frei');
end;

procedure TSelfFreeInEventHandlerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Document: TDfmDocument;
  Events: TArray<TFormEvent>;
  ClassName, Parent: string;
  IsForm: Boolean;
  Variables: TArray<string>;
  Prop: TDfmProperty;
  ClassNode: TSyntaxNode;
  Symbol: TIndexSymbol;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Gibt die Anweisung das Formular selbst frei?
  function FreesSelf(const AStatement: string): Boolean;
  var
    Text, Name: string;
  begin
    Text := LowerCase(StringReplace(StringReplace(StringReplace(AStatement, ' ', '', [rfReplaceAll]), #9, '',
      [rfReplaceAll]), ';', '', [rfReplaceAll]));
    Text := StringReplace(StringReplace(Text, #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]);
    if MatchStr(Text, ['free', 'self.free', 'destroy', 'self.destroy', 'disposeof', 'self.disposeof',
      'freeandnil(self)']) then
      Exit(True);
    for Name in Variables do
      if MatchStr(Text, [LowerCase(Name) + '.free', LowerCase(Name) + '.destroy', LowerCase(Name) + '.disposeof',
        'freeandnil(' + LowerCase(Name) + ')']) then
        Exit(True);
    Result := False;
  end;

  // Ereignis der Formulardatei, das AMethod als Handler hat; '' ohne.
  function EventOf(const AMethod: string): string;
  var
    Event: TFormEvent;
  begin
    for Event in Events do
      if SameText(Event.Handler, AMethod) then
        Exit(Event.Event);
    Result := '';
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Method, Event, Header, What, Replacement, Title: string;
    Body: TSyntaxNode;
    Statements: TArray<TSyntaxNode>;
    Statement: TSyntaxNode;
    IsClose: Boolean;
  begin
    if not StartsText(ClassName + '.', ARoutine.Name) then
      Exit;
    Method := Copy(ARoutine.Name, Length(ClassName) + 2, MaxInt);
    if Pos('.', Method) > 0 then
      Exit;
    Body := ARoutine.FindChild(TSyntaxKind.Block);
    if Body = nil then
      Exit;
    Header := LowerCase(StringReplace(Copy(AContext.Text, ARoutine.StartOffset + 1, Body.StartOffset -
      ARoutine.StartOffset), ' ', '', [rfReplaceAll]));
    Event := EventOf(Method);
    if (Event = '') and not ContainsStr(Header, 'sender:tobject') then
      Exit;
    IsClose := ContainsStr(Header, 'varaction:tcloseaction');
    Statements := nil;
    Body.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind = TSyntaxKind.CallStatement then
          Statements := Statements + [ANode];
        // Anonyme Methoden laufen später, with lenkt Free auf ein anderes Objekt um.
        Result := not (ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement,
          TSyntaxKind.RoutineDecl]);
      end);
    What := 'Ereignis-Handler';
    if StartsText('On', Event) and (Length(Event) > 2) then
      What := Copy(Event, 3, MaxInt) + '-Handler';
    for Statement in Statements do
    begin
      if not FreesSelf(NodeText(Statement)) then
        Continue;
      Replacement := 'Release';
      Title := 'Free durch Release ersetzen';
      if IsClose then
      begin
        Replacement := 'Action := caFree';
        Title := 'Durch Action := caFree ersetzen';
      end;
      AReport.Add(TTextRange.Create(Statement.StartPos, Statement.EndPos),
        Format('Das Formular gibt sich im eigenen %s frei; die VCL greift danach noch darauf zu.', [What]),
        TRuleConfidence.High, [TRuleFix.Create(Title, [TRuleEdit.Create(TTextRange.Create(Statement.StartPos,
        Statement.EndPos), Replacement)], True)]);
    end;
  end;

var
  Routine: TSyntaxNode;
  Cache: IRuleDerivedCache;
begin
  if (AContext.FormText = '') or (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'Free') or ContainsText(AContext.Text, 'Destroy') or
    ContainsText(AContext.Text, 'DisposeOf')) then
    Exit;
  Document := TDfmParser.Parse(AContext.FormText);
  try
    if Document.Root = nil then
      Exit;
    ClassName := Document.Root.TypeName;
    IsForm := False;
    for Prop in Document.Root.Properties do
      if SameText(Prop.Name, 'ClientWidth') or SameText(Prop.Name, 'ClientHeight') then
        IsForm := True;
    Events := nil;
    CollectEvents(Document.Root, True, ClassName, Events);
  finally
    Document.Free;
  end;
  ClassNode := FindClassDecl(AContext.Tree.Root, ClassName);
  if ClassNode = nil then
    Exit;
  if (ClassNode.ChildCount > 0) and (ClassNode[0].Kind = TSyntaxKind.TypeReference) then
  begin
    Parent := ClassNode[0].Name;
    if MatchText(Parent, ['TForm', 'TCustomForm', 'Vcl.Forms.TForm', 'FMX.Forms.TForm']) then
      IsForm := True
    else if MatchText(Parent, ['TFrame', 'TDataModule', 'Vcl.Forms.TFrame', 'System.Classes.TDataModule']) then
      IsForm := False;
  end;
  if not IsForm then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Variables := nil;
  for Symbol in TRuleDerived.UnitIndex(Cache, AContext).Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Variable) and (Symbol.Container = '') and SameText(Symbol.TypeName, ClassName) then
      Variables := Variables + [Symbol.Name];
  for Routine in TRuleDerived.Routines(Cache, AContext) do
    CheckRoutine(Routine);
end;

procedure RegisterFormRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFormResourceMissingRule.Create);
  ARegistry.Register(TFormAutoCreateAndManualRule.Create);
  ARegistry.Register(TInheritedFormHandlerRule.Create);
  ARegistry.Register(TSelfFreeInEventHandlerRule.Create);
end;

end.
