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
  Atlas.Common.Rules.Builtin.FormReferences,
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
        begin
          Exit;
        end;
        Continue;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        if Node.Children[Index].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.InterfaceSection,
          TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
        begin
          Pending.Push(Node.Children[Index]);
        end;
      end;
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
  begin
    Exit;
  end;
  Document := TDfmParser.Parse(AFormText);
  try
    if Document.Root <> nil then
    begin
      Result := Document.Root.TypeName;
    end;
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
  begin
    Path := AContext.RelativePath;
  end;
  Result := ChangeFileExt(ExtractFileName(StringReplace(Path, '/', '\', [rfReplaceAll])), '');
  if Result = '' then
  begin
    Result := AContext.UnitName;
  end;
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
  begin
    Exit;
  end;
  Text := Trim(Copy(Text, Pos(' ', Text) + 1, Length(Text) - Pos(' ', Text) - 1));
  // {$R 'a.dfm'} bzw. {$R *.Windows.fmx MSWINDOWS}: nur die erste Angabe.
  if StartsText('''', Text) then
  begin
    Text := Copy(Text, 2, Pos('''', Copy(Text, 2, MaxInt)) - 1);
  end
  else if Pos(' ', Text) > 0 then
  begin
    Text := Copy(Text, 1, Pos(' ', Text) - 1);
  end;
  if not (EndsText('.dfm', Text) or EndsText('.fmx', Text)) then
  begin
    Exit;
  end;
  if StartsText('*', Text) then
  begin
    if AUnitFile = '' then
    begin
      Exit;
    end;
    Text := AUnitFile + Copy(Text, 2, MaxInt);
  end;
  AFileName := Text;
  Result := True;
end;

/// <summary>Meldet eingebundene Formulardateien, die neben der Unit fehlen (wie F1026). AIncluded: ein {$R}
/// bindet eine Formulardatei ein; AImplementation: das erste implementation. False ohne implementation.</summary>
function ScanFormResources(const AContext: TRuleContext; const AReport: IRuleReport; const AUnitFile: string;
  out AIncluded: Boolean; out AImplementation: TPascalToken): Boolean;
var
  mToken: TPascalToken;
  mFileName: string;
  mData: TBytes;
begin
  Result := False;
  AIncluded := False;
  AImplementation := Default(TPascalToken);
  for mToken in AContext.Tree.Tokens do
  begin
    if not Result and (mToken.Kind = TPascalTokenKind.Keyword) and mToken.IsKeyword('implementation') then
    begin
      Result := True;
      AImplementation := mToken;
    end
    else if (mToken.Kind = TPascalTokenKind.Directive) and
      TFormResourceMissingRule.FormResource(mToken.Text, AUnitFile, mFileName) then
    begin
      AIncluded := True;
      if Assigned(AContext.ReadFile) and not AContext.ReadFile(mFileName, mData) then
      begin
        AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos),
          Format('%s fehlt; der Compiler bricht mit F1026 ab.', [ExtractFileName(mFileName)]));
      end;
    end;
  end;
end;

/// <summary>Endung der Formulardatei: .fmx bei FireMonkey, sonst .dfm.</summary>
function FormExtension(const AContext: TRuleContext): string;
begin
  Result := '.dfm';
  if SameText(ExtractFileExt(AContext.FormFile), '.fmx') then
  begin
    Result := '.fmx';
  end;
end;

/// <summary>Name der Formulardatei ohne Endung: die gefundene Datei, sonst wie die Unit.</summary>
function FormBaseName(const AContext: TRuleContext; const AUnitFile: string): string;
begin
  Result := AUnitFile;
  if AContext.FormFile <> '' then
  begin
    Result := ChangeFileExt(ExtractFileName(AContext.FormFile), '');
  end;
end;

procedure TFormResourceMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mImplementation: TPascalToken;
  mIncluded: Boolean;
  mUnitFile, mClassName, mExtension, mLineBreak: string;
  mFix: TRuleFix;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Tree.Root.Kind <> TSyntaxKind.UnitFile) then
  begin
    Exit;
  end;
  mUnitFile := UnitFileBase(AContext);
  if not ScanFormResources(AContext, AReport, mUnitFile, mIncluded, mImplementation) or mIncluded then
  begin
    Exit;
  end;
  mClassName := FormClassName(AContext.FormText);
  if (mClassName = '') or (FindClassDecl(AContext.Tree.Root, mClassName) = nil) then
  begin
    Exit;
  end;
  mExtension := FormExtension(AContext);
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mFix := TRuleFix.Create('{$R *' + mExtension + '} nach implementation einfügen',
    [TRuleEdit.Create(TTextRange.Create(mImplementation.EndPos, mImplementation.EndPos),
    mLineBreak + mLineBreak + '{$R *' + mExtension + '}')], True);
  AReport.Add(TTextRange.Create(mImplementation.StartPos, mImplementation.EndPos),
    Format('%s wird nicht eingebunden; %s.Create löst EResNotFound aus.', [FormBaseName(AContext, mUnitFile) +
    mExtension, mClassName]), TRuleConfidence.High, [mFix]);
end;

/// <summary>Deklariert der Knoten ANode (Variable, Parameter, Konstante) den Namen AName?</summary>
function DeclaresLocalName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter, TSyntaxKind.ConstDecl] then
  begin
    for mName in SplitString(ANode.Name, ',') do
    begin
      Result := Result or SameText(Trim(mName), AName);
    end;
  end;
end;

/// <summary>Deklariert die Routine AName selbst (Parameter, lokale Variable, Konstante)? Iterativ
/// (Bericht M1).</summary>
function DeclaresLocally(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while not Result and (mPending.Count > 0) do
    begin
      mNode := mPending.Pop;
      for mIndex := 0 to mNode.ChildCount - 1 do
      begin
        Result := Result or DeclaresLocalName(mNode[mIndex], AName);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        if mNode[mIndex].Kind <> TSyntaxKind.Block then
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Indizes der Code-Token (ohne Kommentare und Direktiven).</summary>
function CodeIndexes(const ATokens: TArray<TPascalToken>): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(ATokens) do
  begin
    if not (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result := Result + [Index];
    end;
  end;
end;

function IntInArray(AValue: Integer; const AValues: TArray<Integer>): Boolean;
var
  Value: Integer;
begin
  for Value in AValues do
  begin
    if Value = AValue then
    begin
      Exit(True);
    end;
  end;
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
    begin
      Result := Tokens[Code[APosition]].Text;
    end;
  end;

  // Application.CreateForm(TKlasse, Variable) ab dem Code-Token APosition?
  function IsCreateFormAt(APosition: Integer): Boolean;
  begin
    Result := SameText(Text(APosition), 'Application') and (Text(APosition + 1) = '.') and
      SameText(Text(APosition + 2), 'CreateForm') and (Text(APosition + 3) = '(');
    Result := Result and (Text(APosition + 5) = ',') and (Text(APosition + 7) = ')') and
      (Tokens[Code[APosition + 6]].Kind = TPascalTokenKind.Identifier);
  end;

begin
  Result := nil;
  Tokens := TPascalLexer.Tokenize(AMainSource);
  Code := CodeIndexes(Tokens);
  Lines := TTextLines.SplitLines(AMainSource);
  for Position := 0 to High(Code) - 7 do
  begin
    if IsCreateFormAt(Position) then
    begin
      Call := Default(TCreateFormCall);
      Call.TypeName := Text(Position + 4);
      Call.Variable := Text(Position + 6);
      Last := Position + 7;
      if Text(Position + 8) = ';' then
      begin
        Last := Position + 8;
      end;
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
      begin
        Call.Range := TTextRange.Create(Call.Range.StartPos.Line, 0, Call.Range.StartPos.Line + 1, 0);
      end;
      Result := Result + [Call];
    end;
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
      begin
        Result := mMiddle + 1;
      end
      else
      begin
        mHigh := mMiddle;
      end;
    end;
  end;

  function FindCall(const AVariable: string; out ACall: TCreateFormCall): Boolean;
  var
    Call: TCreateFormCall;
  begin
    for Call in Calls do
    begin
      if SameText(Call.Variable, AVariable) then
      begin
        ACall := Call;
        Exit(True);
      end;
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
    begin
      Exit;
    end;
    Owner := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    for Symbol in Local.Symbols do
    begin
      if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and SameText(Symbol.Name, AName) and
        SameText(Symbol.Container, Owner) then
      begin
        Exit(True);
      end;
    end;
  end;

  // Assigned(V) oder FreeAndNil(V) beim Code-Token APosition?
  function InAssignedOrFree(APosition: Integer): Boolean;
  begin
    Result := IsSym(APosition - 1, '(') and (IsName(APosition - 2, 'Assigned') or IsName(APosition - 2, 'FreeAndNil'));
  end;

  // V = nil oder V <> nil beim Code-Token APosition?
  function ComparedWithNil(APosition: Integer): Boolean;
  begin
    Result := (IsSym(APosition + 1, '<>') or IsSym(APosition + 1, '=')) and (APosition + 2 <= High(Code)) and
      Token(APosition + 2).IsKeyword('nil');
  end;

  // V.Free, V.Release oder V.DisposeOf beim Code-Token APosition?
  function FreedAt(APosition: Integer): Boolean;
  begin
    Result := IsSym(APosition + 1, '.') and (IsName(APosition + 2, 'Free') or IsName(APosition + 2, 'Release') or
      IsName(APosition + 2, 'DisposeOf'));
  end;

  // Prüft oder gibt die Routine die Variable frei (Assigned, nil-Vergleich, Free, FreeAndNil, Release)?
  function Handled(AFirst, ALast: Integer; const AName: string): Boolean;
  var
    mPosition: Integer;
  begin
    Result := False;
    mPosition := AFirst;
    while not Result and (mPosition <= ALast) do
    begin
      Result := IsName(mPosition, AName) and not IsSym(mPosition - 1, '.') and (InAssignedOrFree(mPosition) or
        ComparedWithNil(mPosition) or FreedAt(mPosition));
      Inc(mPosition);
    end;
  end;

  // V := TKlasse.Create(…) beim Code-Token APosition?
  function IsCreateAssignment(APosition: Integer): Boolean;
  begin
    Result := (Token(APosition).Kind = TPascalTokenKind.Identifier) and not IsSym(APosition - 1, '.') and
      IsSym(APosition + 1, ':=');
    Result := Result and (Token(APosition + 2).Kind = TPascalTokenKind.Identifier) and IsSym(APosition + 3, '.') and
      IsName(APosition + 4, 'Create');
  end;

  // Ist AName ein automatisch erzeugtes Formular, das die Routine weder selbst deklariert noch prüft oder freigibt?
  function IsUnhandledForm(ARoutine: TSyntaxNode; AFirst, ALast: Integer; const AName: string): Boolean;
  begin
    Result := MatchText(AName, AContext.AutoCreateForms) and not DeclaresLocally(ARoutine, AName) and
      not IsMember(ARoutine, AName) and not Handled(AFirst, ALast, AName);
  end;

  procedure ReportCreate(APosition: Integer; AHasCall: Boolean; const ACall: TCreateFormCall);
  var
    mFixes: TArray<TRuleFix>;
  begin
    Reported := Reported + [APosition];
    mFixes := nil;
    if AHasCall then
    begin
      mFixes := [TRuleFix.Create(ACall.Statement + ' aus ' + MainName + ' entfernen',
        [TRuleEdit.Create(ACall.Range, '')])];
      mFixes[0].FileName := AContext.ProjectMainSource;
    end;
    AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(APosition + 4).EndPos),
      Format('%s wird schon in %s erzeugt; hier entsteht eine zweite Instanz.', [Token(APosition).Text, MainName]),
      TRuleConfidence.High, mFixes);
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    mBody: TSyntaxNode;
    mFirst, mLast, mPosition: Integer;
    mName: string;
    mCall: TCreateFormCall;
    mHasCall: Boolean;
  begin
    mBody := TRoutineBody.BodyOf(ARoutine);
    if mBody = nil then
    begin
      Exit;
    end;
    mFirst := CodeAt(mBody.StartOffset);
    mLast := CodeAt(mBody.EndOffset) - 1;
    for mPosition := mFirst to mLast - 4 do
    begin
      // Verschachtelte Routinen liegen im Rumpf der äußeren: jede Stelle einmal.
      if not IsCreateAssignment(mPosition) or IntInArray(mPosition, Reported) then
      begin
        Continue;
      end;
      mName := Token(mPosition).Text;
      mHasCall := FindCall(mName, mCall);
      if (mHasCall and not SameText(mCall.TypeName, Token(mPosition + 2).Text)) or
        not IsUnhandledForm(ARoutine, mFirst, mLast, mName) then
      begin
        Continue;
      end;
      ReportCreate(mPosition, mHasCall, mCall);
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Code := CodeIndexes(Tokens);
  Calls := nil;
  MainName := 'der .dpr';
  if AContext.ProjectName <> '' then
  begin
    MainName := AContext.ProjectName + '.dpr';
  end;
  if AContext.ProjectMainSource <> '' then
  begin
    MainName := ExtractFileName(AContext.ProjectMainSource);
    if Assigned(AContext.ReadFile) and AContext.ReadFile(AContext.ProjectMainSource, Data) then
    begin
      Calls := CreateFormCalls(TFileEncoding.Decode(Data, Format_));
    end;
  end;
  Cache := TRuleDerived.Open(AContext);
  Local := TRuleDerived.UnitIndex(Cache, AContext);
  Reported := nil;
  for Routine in TRuleDerived.Routines(Cache, AContext) do
  begin
    CheckRoutine(Routine);
  end;
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
  begin
    Exit;
  end;
  for Prop in AObject.Properties do
  begin
    if Prop.IsEvent then
    begin
      Event := Default(TFormEvent);
      if not AIsRoot then
      begin
        Event.Component := AObject.Name;
      end;
      Event.Event := Prop.Name;
      Event.Handler := Prop.Value;
      Event.Owner := AOwner;
      AEvents := AEvents + [Event];
    end;
  end;
  for Child in AObject.Children do
  begin
    CollectEvents(Child, False, AOwner, AEvents);
  end;
end;

function TInheritedFormHandlerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-form-handler-without-inherited', TRuleSeverity.Warning,
    'Ereignis-Handler im geerbten Formular ohne inherited');
end;

type
  /// <summary>Token eines Handlers: sein Name im Kopf, das begin des Rumpfs und ob der Rumpf inherited
  /// aufruft.</summary>
  THandlerTokens = record
    NameToken: TPascalToken;
    BeginToken: TPascalToken;
    HasName: Boolean;
    HasBegin: Boolean;
    HasInherited: Boolean;
  end;

procedure TInheritedFormHandlerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Inherited_: TArray<TFormEvent>;
  UsedUnits: TArray<string>;

  // Units, in denen der Index die Klasse AName deklariert, ohne Endung.
  function IndexedUnits(const AName: string): TArray<string>;
  var
    mLocation: TSymbolLocation;
  begin
    Result := nil;
    if AContext.Index = nil then
    begin
      Exit;
    end;
    for mLocation in AContext.Index.FindSymbols(AName) do
    begin
      if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') then
      begin
        Result := Result + [ChangeFileExt(mLocation.FileName, '')];
      end;
    end;
  end;

  // Formulardatei ABase mit .dfm bzw. .fmx, deren Wurzel die Klasse AName ist.
  function FormOf(const ABase, AName: string; out AText, AFileName: string): Boolean;
  var
    mExtension: string;
    mData: TBytes;
    mFormat: TFileFormat;
    mParsed: TDfmDocument;
  begin
    Result := False;
    AText := '';
    AFileName := '';
    for mExtension in TArray<string>.Create('.dfm', '.fmx') do
    begin
      if Result or not AContext.ReadFile(ABase + mExtension, mData) then
      begin
        Continue;
      end;
      AText := TFileEncoding.Decode(mData, mFormat);
      mParsed := TDfmParser.Parse(AText);
      try
        Result := (mParsed.Root <> nil) and SameText(mParsed.Root.TypeName, AName);
      finally
        mParsed.Free;
      end;
      if Result then
      begin
        AFileName := ABase + mExtension;
      end;
    end;
  end;

  // Formulardatei der Klasse AClassName: über den Index, sonst über die Units AUnits neben der Unit.
  function AncestorForm(const AClassName: string; const AUnits: TArray<string>; out AText, AFileName: string):
    Boolean;
  var
    mCandidates: TArray<string>;
    mCandidate, mName: string;
  begin
    Result := False;
    AText := '';
    AFileName := '';
    if not Assigned(AContext.ReadFile) then
    begin
      Exit;
    end;
    mName := Copy(AClassName, LastDelimiter('.', AClassName) + 1, MaxInt);
    mCandidates := IndexedUnits(mName) + AUnits;
    for mCandidate in mCandidates do
    begin
      if FormOf(mCandidate, mName, AText, AFileName) then
      begin
        Exit(True);
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
    begin
      Exit;
    end;
    Text := TFileEncoding.Decode(Data, Format_);
    AUnits := TUsesClauses.UsedUnits(TPascalLexer.Tokenize(Text));
    Match := TRegEx.Match(Text, '\b' + AClassName + '\s*=\s*class\s*\(\s*([\w.]+)', [roIgnoreCase]);
    if Match.Success then
    begin
      Result := Match.Groups[1].Value;
    end;
  end;

  function FindInherited(const AEvent: TFormEvent; out AFound: TFormEvent): Boolean;
  var
    Event: TFormEvent;
  begin
    for Event in Inherited_ do
    begin
      if SameText(Event.Component, AEvent.Component) and SameText(Event.Event, AEvent.Event) then
      begin
        AFound := Event;
        Exit(True);
      end;
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
      begin
        Exit;
      end;
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
      begin
        if not FindInherited(Event, Found) then
        begin
          Inherited_ := Inherited_ + [Event];
        end;
      end;
      if not IsInherited then
      begin
        Exit;
      end;
      Parent := ParentInFile(Copy(Parent, LastDelimiter('.', Parent) + 1, MaxInt), FileName, More);
      if Parent = '' then
      begin
        Exit;
      end;
      Units := Units + More;
    end;
  end;

  function FindRoutine(const AName: string): TSyntaxNode;
  var
    Routine: TSyntaxNode;
  begin
    for Routine in TRuleDerived.Routines(TRuleDerived.Open(AContext), AContext) do
    begin
      if SameText(Routine.Name, AName) then
      begin
        Exit(Routine);
      end;
    end;
    Result := nil;
  end;

  // Name, begin und inherited der Routine ARoutine mit dem Rumpf ABody, die den Handler AHandler implementiert.
  function HandlerTokens(ARoutine, ABody: TSyntaxNode; const AHandler: string): THandlerTokens;
  var
    mIndex: Integer;
    mToken: TPascalToken;
  begin
    Result := Default(THandlerTokens);
    for mIndex := AContext.Tree.FirstTokenFrom(ARoutine.StartOffset) to High(AContext.Tree.Tokens) do
    begin
      mToken := AContext.Tree.Tokens[mIndex];
      if (mToken.Offset < ARoutine.StartOffset) or (mToken.Offset >= ARoutine.EndOffset) or
        (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      begin
        Continue;
      end;
      if not Result.HasName and (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, AHandler) then
      begin
        Result.HasName := True;
        Result.NameToken := mToken;
      end;
      if not Result.HasBegin and (mToken.Offset >= ABody.StartOffset) and mToken.IsKeyword('begin') then
      begin
        Result.HasBegin := True;
        Result.BeginToken := mToken;
      end;
      Result.HasInherited := Result.HasInherited or ((mToken.Offset >= ABody.StartOffset) and
        mToken.IsKeyword('inherited'));
    end;
  end;

  // Ereignisse der eigenen Formulardatei, wenn sie geerbt ist (inherited); AClassName: ihre Klasse.
  function OwnEvents(out AClassName: string): TArray<TFormEvent>;
  var
    mDocument: TDfmDocument;
  begin
    Result := nil;
    AClassName := '';
    mDocument := TDfmParser.Parse(AContext.FormText);
    try
      if (mDocument.Root <> nil) and (mDocument.Root.Kind = TDfmObjectKind.Inherited_) then
      begin
        AClassName := mDocument.Root.TypeName;
        CollectEvents(mDocument.Root, True, AClassName, Result);
      end;
    finally
      mDocument.Free;
    end;
  end;

  procedure ReportHandler(const AAncestor: TFormEvent; const ATokens: THandlerTokens);
  var
    mFixes: TArray<TRuleFix>;
    mLineBreak: string;
  begin
    mFixes := nil;
    if ATokens.HasBegin then
    begin
      mLineBreak := TTextLines.LineBreakOf(AContext.Text);
      mFixes := [TRuleFix.Create('inherited; am Anfang einfügen', [TRuleEdit.Create(TTextRange.Create(
        ATokens.BeginToken.EndPos, ATokens.BeginToken.EndPos), mLineBreak +
        TTextLines.IndentOf(AContext.Text, ATokens.BeginToken.StartPos.Line) + '  inherited;')], True)];
    end;
    AReport.Add(TTextRange.Create(ATokens.NameToken.StartPos, ATokens.NameToken.EndPos),
      Format('%s.%s wird nicht mehr ausgeführt (kein inherited).', [AAncestor.Owner, AAncestor.Handler]),
      TRuleConfidence.High, mFixes);
  end;

  // Meldet den Handler von AEvent, wenn er den gleichnamigen Handler des Vorfahren ohne inherited ersetzt.
  procedure CheckEvent(const AEvent: TFormEvent; const AClassName: string);
  var
    mAncestor: TFormEvent;
    mRoutine, mBody: TSyntaxNode;
    mTokens: THandlerTokens;
  begin
    // Nur gleichnamige Handler: ein anderer Name ersetzt den Handler des Vorfahren bewusst.
    if not FindInherited(AEvent, mAncestor) or not SameText(mAncestor.Handler, AEvent.Handler) then
    begin
      Exit;
    end;
    mRoutine := FindRoutine(AClassName + '.' + AEvent.Handler);
    mBody := nil;
    if mRoutine <> nil then
    begin
      mBody := TRoutineBody.BodyOf(mRoutine);
    end;
    if mBody = nil then
    begin
      Exit;
    end;
    mTokens := HandlerTokens(mRoutine, mBody, AEvent.Handler);
    if not mTokens.HasInherited and mTokens.HasName then
    begin
      ReportHandler(mAncestor, mTokens);
    end;
  end;

var
  mClassNode: TSyntaxNode;
  mClassName: string;
  mOwn: TArray<TFormEvent>;
  mEvent: TFormEvent;
begin
  if (AContext.FormText = '') or (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not ContainsText(AContext.FormText, 'inherited') then
  begin
    Exit;
  end;
  mOwn := OwnEvents(mClassName);
  if Length(mOwn) = 0 then
  begin
    Exit;
  end;
  mClassNode := FindClassDecl(AContext.Tree.Root, mClassName);
  if (mClassNode = nil) or (mClassNode.ChildCount = 0) or (mClassNode[0].Kind <> TSyntaxKind.TypeReference) then
  begin
    Exit;
  end;
  UsedUnits := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  Inherited_ := nil;
  CollectAncestors(mClassNode[0].Name);
  for mEvent in mOwn do
  begin
    CheckEvent(mEvent, mClassName);
  end;
end;

{ TSelfFreeInEventHandlerRule }

function TSelfFreeInEventHandlerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('self-free-in-event-handler', TRuleSeverity.Error,
    'Formular gibt sich im eigenen Ereignis frei');
end;

/// <summary>Kommt Free, Destroy oder DisposeOf im Text vor?</summary>
function MentionsFree(const AText: string): Boolean;
begin
  Result := ContainsText(AText, 'Free') or ContainsText(AText, 'Destroy') or ContainsText(AText, 'DisposeOf');
end;

procedure TSelfFreeInEventHandlerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Events: TArray<TFormEvent>;
  ClassName: string;
  Variables: TArray<string>;

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
    begin
      Exit(True);
    end;
    for Name in Variables do
    begin
      if MatchStr(Text, [LowerCase(Name) + '.free', LowerCase(Name) + '.destroy', LowerCase(Name) + '.disposeof',
        'freeandnil(' + LowerCase(Name) + ')']) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Ereignis der Formulardatei, das AMethod als Handler hat; '' ohne.
  function EventOf(const AMethod: string): string;
  var
    Event: TFormEvent;
  begin
    for Event in Events do
    begin
      if SameText(Event.Handler, AMethod) then
      begin
        Exit(Event.Event);
      end;
    end;
    Result := '';
  end;

  // Rumpf ABody eines Handlers der Klasse: ein Ereignis der Formulardatei (AEvent) oder eine Methode mit
  // Sender: TObject; AIsClose: OnClose mit var Action: TCloseAction.
  function HandlerOf(ARoutine: TSyntaxNode; out AEvent: string; out ABody: TSyntaxNode; out AIsClose: Boolean):
    Boolean;
  var
    mMethod, mHeader: string;
  begin
    Result := False;
    AEvent := '';
    AIsClose := False;
    ABody := ARoutine.FindChild(TSyntaxKind.Block);
    mMethod := Copy(ARoutine.Name, Length(ClassName) + 2, MaxInt);
    if not StartsText(ClassName + '.', ARoutine.Name) or (Pos('.', mMethod) > 0) or (ABody = nil) then
    begin
      Exit;
    end;
    mHeader := LowerCase(StringReplace(Copy(AContext.Text, ARoutine.StartOffset + 1, ABody.StartOffset -
      ARoutine.StartOffset), ' ', '', [rfReplaceAll]));
    AEvent := EventOf(mMethod);
    AIsClose := ContainsStr(mHeader, 'varaction:tcloseaction');
    Result := (AEvent <> '') or ContainsStr(mHeader, 'sender:tobject');
  end;

  // Aufrufanweisungen im Rumpf ABody. Anonyme Methoden laufen später, with lenkt Free auf ein anderes Objekt um.
  function CallStatements(ABody: TSyntaxNode): TArray<TSyntaxNode>;
  var
    mStatements: TArray<TSyntaxNode>;
  begin
    mStatements := nil;
    ABody.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind = TSyntaxKind.CallStatement then
        begin
          mStatements := mStatements + [ANode];
        end;
        Result := not (ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement,
          TSyntaxKind.RoutineDecl]);
      end);
    Result := mStatements;
  end;

  procedure ReportFree(AStatement: TSyntaxNode; const AEvent: string; AIsClose: Boolean);
  var
    mWhat, mReplacement, mTitle: string;
  begin
    mWhat := 'Ereignis-Handler';
    if StartsText('On', AEvent) and (Length(AEvent) > 2) then
    begin
      mWhat := Copy(AEvent, 3, MaxInt) + '-Handler';
    end;
    mReplacement := 'Release';
    mTitle := 'Free durch Release ersetzen';
    if AIsClose then
    begin
      mReplacement := 'Action := caFree';
      mTitle := 'Durch Action := caFree ersetzen';
    end;
    AReport.Add(TTextRange.Create(AStatement.StartPos, AStatement.EndPos),
      Format('Das Formular gibt sich im eigenen %s frei; die VCL greift danach noch darauf zu.', [mWhat]),
      TRuleConfidence.High, [TRuleFix.Create(mTitle, [TRuleEdit.Create(TTextRange.Create(AStatement.StartPos,
      AStatement.EndPos), mReplacement)], True)]);
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    mEvent: string;
    mBody, mStatement: TSyntaxNode;
    mIsClose: Boolean;
  begin
    if not HandlerOf(ARoutine, mEvent, mBody, mIsClose) then
    begin
      Exit;
    end;
    for mStatement in CallStatements(mBody) do
    begin
      if FreesSelf(NodeText(mStatement)) then
      begin
        ReportFree(mStatement, mEvent, mIsClose);
      end;
    end;
  end;

  // Liest Klasse und Ereignisse der Formulardatei; AIsForm: mit ClientWidth bzw. ClientHeight. False ohne Wurzel.
  function ReadForm(out AIsForm: Boolean): Boolean;
  var
    mDocument: TDfmDocument;
    mProp: TDfmProperty;
  begin
    AIsForm := False;
    mDocument := TDfmParser.Parse(AContext.FormText);
    try
      Result := mDocument.Root <> nil;
      if not Result then
      begin
        Exit;
      end;
      ClassName := mDocument.Root.TypeName;
      for mProp in mDocument.Root.Properties do
      begin
        AIsForm := AIsForm or SameText(mProp.Name, 'ClientWidth') or SameText(mProp.Name, 'ClientHeight');
      end;
      Events := nil;
      CollectEvents(mDocument.Root, True, ClassName, Events);
    finally
      mDocument.Free;
    end;
  end;

  // Formular nach dem Vorfahren der Klasse AClassNode; sonst bleibt es bei AIsForm aus der Formulardatei.
  function IsFormClass(AClassNode: TSyntaxNode; AIsForm: Boolean): Boolean;
  var
    mParent: string;
  begin
    Result := AIsForm;
    if (AClassNode.ChildCount = 0) or (AClassNode[0].Kind <> TSyntaxKind.TypeReference) then
    begin
      Exit;
    end;
    mParent := AClassNode[0].Name;
    if MatchText(mParent, ['TForm', 'TCustomForm', 'Vcl.Forms.TForm', 'FMX.Forms.TForm']) then
    begin
      Result := True;
    end
    else if MatchText(mParent, ['TFrame', 'TDataModule', 'Vcl.Forms.TFrame', 'System.Classes.TDataModule']) then
    begin
      Result := False;
    end;
  end;

  // Globale Variablen der Unit vom Typ der Klasse.
  function FormVariables(const ACache: IRuleDerivedCache): TArray<string>;
  var
    mSymbol: TIndexSymbol;
  begin
    Result := nil;
    for mSymbol in TRuleDerived.UnitIndex(ACache, AContext).Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Variable) and (mSymbol.Container = '') and
        SameText(mSymbol.TypeName, ClassName) then
      begin
        Result := Result + [mSymbol.Name];
      end;
    end;
  end;

var
  mRoutine, mClassNode: TSyntaxNode;
  mCache: IRuleDerivedCache;
  mIsForm: Boolean;
begin
  if (AContext.FormText = '') or (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not MentionsFree(AContext.Text) or not ReadForm(mIsForm) then
  begin
    Exit;
  end;
  mClassNode := FindClassDecl(AContext.Tree.Root, ClassName);
  if (mClassNode = nil) or not IsFormClass(mClassNode, mIsForm) then
  begin
    Exit;
  end;
  mCache := TRuleDerived.Open(AContext);
  Variables := FormVariables(mCache);
  for mRoutine in TRuleDerived.Routines(mCache, AContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

procedure RegisterFormRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFormResourceMissingRule.Create);
  ARegistry.Register(TFormAutoCreateAndManualRule.Create);
  ARegistry.Register(TInheritedFormHandlerRule.Create);
  ARegistry.Register(TSelfFreeInEventHandlerRule.Create);
  // dfm-reference-unit-missing gehört zur Gruppe forms, steht aber in eigener Unit.
  ARegistry.Register(TDfmReferenceUnitMissingRule.Create);
end;

end.
