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
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFormsText = (ResourceTitle, Missing, NotIncluded, TwiceTitle, SecondInstance, TheDpr, InheritedTitle,
    InsertInherited, NotExecuted, SelfFreeTitle, FreeToRelease, ReplaceCaFree, FreesItself, EventHandler,
    HandlerSuffix, InsertResource, RemoveFromMain);

const
  cTexts: array[TFormsText] of TAtlasText = (
    (De: 'Formular-Unit ohne {$R *.dfm} bzw. {$R} ohne Formulardatei';
     En: 'Form unit without {$R *.dfm} or {$R} without form file'),
    (De: '%s fehlt; der Compiler bricht mit F1026 ab.'; En: '%s is missing; the compiler stops with F1026.'),
    (De: '%s wird nicht eingebunden; %s.Create löst EResNotFound aus.';
     En: '%s is not included; %s.Create raises EResNotFound.'),
    (De: 'Formular automatisch und zusätzlich von Hand erzeugt';
     En: 'Form created automatically and additionally by hand'),
    (De: '%s wird schon in %s erzeugt; hier entsteht eine zweite Instanz.';
     En: '%s is already created in %s; a second instance is created here.'),
    (De: 'der .dpr'; En: 'the .dpr'),
    (De: 'Ereignis-Handler im geerbten Formular ohne inherited';
     En: 'Event handler in the inherited form without inherited'),
    (De: 'inherited; am Anfang einfügen'; En: 'Insert inherited; at the start'),
    (De: '%s.%s wird nicht mehr ausgeführt (kein inherited).'; En: '%s.%s is no longer executed (no inherited).'),
    (De: 'Formular gibt sich im eigenen Ereignis frei'; En: 'Form frees itself in its own event'),
    (De: 'Free durch Release ersetzen'; En: 'Replace Free with Release'),
    (De: 'Durch Action := caFree ersetzen'; En: 'Replace with Action := caFree'),
    (De: 'Das Formular gibt sich im eigenen %s frei; die VCL greift danach noch darauf zu.';
     En: 'The form frees itself in its own %s; the VCL still accesses it afterwards.'),
    (De: 'Ereignis-Handler'; En: 'event handler'),
    (De: '-Handler'; En: ' handler'),
    (De: '{$R *%s} nach implementation einfügen'; En: 'Insert {$R *%s} after implementation'),
    (De: '%s aus %s entfernen'; En: 'Remove %s from %s'));

{$SCOPEDENUMS OFF}

/// <summary>Klasse ATypeName der Unit (Interface oder Implementation), sonst nil. Iterativ (Bericht M1).
/// </summary>
function FindClassDecl(ANode: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, ATypeName) then
      begin
        Result := mNode.FindChild(TSyntaxKind.ClassType);
        if Result <> nil then
        begin
          Exit;
        end;
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        if mNode.Children[mIndex].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.InterfaceSection,
          TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
        begin
          mPending.Push(mNode.Children[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Klassenname des Wurzelobjekts der Formulardatei; '' ohne lesbares Wurzelobjekt.</summary>
function FormClassName(const AFormText: string): string;
var
  mDocument: TDfmDocument;
begin
  Result := '';
  if AFormText = '' then
  begin
    Exit;
  end;
  mDocument := TDfmParser.Parse(AFormText);
  try
    if mDocument.Root <> nil then
    begin
      Result := mDocument.Root.TypeName;
    end;
  finally
    mDocument.Free;
  end;
end;

/// <summary>Dateiname der Unit ohne Endung aus FileName bzw. RelativePath; '' wenn unbekannt.</summary>
function UnitFileBase(const AContext: TRuleContext): string;
var
  mPath: string;
begin
  mPath := AContext.FileName;
  if mPath = '' then
  begin
    mPath := AContext.RelativePath;
  end;
  Result := ChangeFileExt(ExtractFileName(StringReplace(mPath, '/', '\', [rfReplaceAll])), '');
  if Result = '' then
  begin
    Result := AContext.UnitName;
  end;
end;

{ TFormResourceMissingRule }

function TFormResourceMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-resource-missing', TRuleSeverity.Error,
    cTexts[TFormsText.ResourceTitle].Text);
end;

class function TFormResourceMissingRule.FormResource(const ADirective, AUnitFile: string;
  out AFileName: string): Boolean;
var
  mText: string;
begin
  Result := False;
  mText := Trim(ADirective);
  if not (StartsText('{$R ', mText) or StartsText('{$RESOURCE ', mText)) or not EndsText('}', mText) then
  begin
    Exit;
  end;
  mText := Trim(Copy(mText, Pos(' ', mText) + 1, Length(mText) - Pos(' ', mText) - 1));
  // {$R 'a.dfm'} bzw. {$R *.Windows.fmx MSWINDOWS}: nur die erste Angabe.
  if StartsText('''', mText) then
  begin
    mText := Copy(mText, 2, Pos('''', Copy(mText, 2, MaxInt)) - 1);
  end
  else if Pos(' ', mText) > 0 then
  begin
    mText := Copy(mText, 1, Pos(' ', mText) - 1);
  end;
  if not (EndsText('.dfm', mText) or EndsText('.fmx', mText)) then
  begin
    Exit;
  end;
  if StartsText('*', mText) then
  begin
    if AUnitFile = '' then
    begin
      Exit;
    end;
    mText := AUnitFile + Copy(mText, 2, MaxInt);
  end;
  AFileName := mText;
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
          cTexts[TFormsText.Missing].Fmt([ExtractFileName(mFileName)]));
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
  mFix := TRuleFix.Create(cTexts[TFormsText.InsertResource].Fmt([mExtension]),
    [TRuleEdit.Create(TTextRange.Create(mImplementation.EndPos, mImplementation.EndPos),
    mLineBreak + mLineBreak + '{$R *' + mExtension + '}')], True);
  AReport.Add(TTextRange.Create(mImplementation.StartPos, mImplementation.EndPos),
    cTexts[TFormsText.NotIncluded].Fmt([FormBaseName(AContext, mUnitFile) +
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
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    if not (ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function IntInArray(AValue: Integer; const AValues: TArray<Integer>): Boolean;
var
  mValue: Integer;
begin
  for mValue in AValues do
  begin
    if mValue = AValue then
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
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mPosition, mLast: Integer;
  mCall: TCreateFormCall;
  mLines: TArray<string>;
  mLine: string;
  mAlone: Boolean;

  function Text(APosition: Integer): string;
  begin
    Result := '';
    if APosition <= High(mCode) then
    begin
      Result := mTokens[mCode[APosition]].Text;
    end;
  end;

  // Application.CreateForm(TKlasse, Variable) ab dem Code-Token APosition?
  function IsCreateFormAt(APosition: Integer): Boolean;
  begin
    Result := SameText(Text(APosition), 'Application') and (Text(APosition + 1) = '.') and
      SameText(Text(APosition + 2), 'CreateForm') and (Text(APosition + 3) = '(');
    Result := Result and (Text(APosition + 5) = ',') and (Text(APosition + 7) = ')') and
      (mTokens[mCode[APosition + 6]].Kind = TPascalTokenKind.Identifier);
  end;

begin
  Result := nil;
  mTokens := TPascalLexer.Tokenize(AMainSource);
  mCode := CodeIndexes(mTokens);
  mLines := TTextLines.SplitLines(AMainSource);
  for mPosition := 0 to High(mCode) - 7 do
  begin
    if IsCreateFormAt(mPosition) then
    begin
      mCall := Default(TCreateFormCall);
      mCall.TypeName := Text(mPosition + 4);
      mCall.Variable := Text(mPosition + 6);
      mLast := mPosition + 7;
      if Text(mPosition + 8) = ';' then
      begin
        mLast := mPosition + 8;
      end;
      mCall.Statement := 'Application.CreateForm(' + mCall.TypeName + ', ' + mCall.Variable + ')';
      mCall.Range := TTextRange.Create(mTokens[mCode[mPosition]].StartPos, mTokens[mCode[mLast]].EndPos);
      mAlone := mCall.Range.StartPos.Line = mCall.Range.EndPos.Line;
      if mAlone and (mCall.Range.StartPos.Line <= High(mLines)) then
      begin
        mLine := mLines[mCall.Range.StartPos.Line];
        mAlone := (Trim(Copy(mLine, 1, mCall.Range.StartPos.Character)) = '') and
          (Trim(Copy(mLine, mCall.Range.EndPos.Character + 1, MaxInt)) = '');
      end;
      if mAlone and (mCall.Range.StartPos.Line < High(mLines)) then
      begin
        mCall.Range := TTextRange.Create(mCall.Range.StartPos.Line, 0, mCall.Range.StartPos.Line + 1, 0);
      end;
      Result := Result + [mCall];
    end;
  end;
end;

function TFormAutoCreateAndManualRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-autocreate-and-manual', TRuleSeverity.Warning,
    cTexts[TFormsText.TwiceTitle].Text);
end;

procedure TFormAutoCreateAndManualRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mCalls: TArray<TCreateFormCall>;
  mLocal: TUnitIndex;
  mMainName: string;
  mReported: TArray<Integer>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := mTokens[mCode[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  function CodeAt(AOffset: Integer): Integer;
  var
    mHigh, mMiddle: Integer;
  begin
    // Binär statt ab Dateianfang mit einer Kopie je Token: Code steht nach Offset sortiert (#1342).
    Result := 0;
    mHigh := Length(mCode);
    while Result < mHigh do
    begin
      mMiddle := (Result + mHigh) div 2;
      if mTokens[mCode[mMiddle]].Offset < AOffset then
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
    mCall: TCreateFormCall;
  begin
    for mCall in mCalls do
    begin
      if SameText(mCall.Variable, AVariable) then
      begin
        ACall := mCall;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Feld oder Property gleichen Namens in der Klasse der Methode (verdeckt die globale Variable).
  function IsMember(ARoutine: TSyntaxNode; const AName: string): Boolean;
  var
    mSymbol: TIndexSymbol;
    mOwner: string;
  begin
    Result := False;
    if LastDelimiter('.', ARoutine.Name) = 0 then
    begin
      Exit;
    end;
    mOwner := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    for mSymbol in mLocal.Symbols do
    begin
      if (mSymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and SameText(mSymbol.Name, AName) and
        SameText(mSymbol.Container, mOwner) then
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
    Result := (IsSym(APosition + 1, '<>') or IsSym(APosition + 1, '=')) and (APosition + 2 <= High(mCode)) and
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
    mReported := mReported + [APosition];
    mFixes := nil;
    if AHasCall then
    begin
      mFixes := [TRuleFix.Create(cTexts[TFormsText.RemoveFromMain].Fmt([ACall.Statement, mMainName]),
        [TRuleEdit.Create(ACall.Range, '')])];
      mFixes[0].FileName := AContext.ProjectMainSource;
    end;
    AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(APosition + 4).EndPos),
      cTexts[TFormsText.SecondInstance].Fmt([Token(APosition).Text, mMainName]),
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
      if not IsCreateAssignment(mPosition) or IntInArray(mPosition, mReported) then
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
  mData: TBytes;
  mFormat_: TFileFormat;
  mRoutine: TSyntaxNode;
  mCache: IRuleDerivedCache;
begin
  if (Length(AContext.AutoCreateForms) = 0) or (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    (AContext.Tree.Root.Kind = TSyntaxKind.ProgramFile) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCode := CodeIndexes(mTokens);
  mCalls := nil;
  mMainName := cTexts[TFormsText.TheDpr].Text;
  if AContext.ProjectName <> '' then
  begin
    mMainName := AContext.ProjectName + '.dpr';
  end;
  if AContext.ProjectMainSource <> '' then
  begin
    mMainName := ExtractFileName(AContext.ProjectMainSource);
    if Assigned(AContext.ReadFile) and AContext.ReadFile(AContext.ProjectMainSource, mData) then
    begin
      mCalls := CreateFormCalls(TFileEncoding.Decode(mData, mFormat_));
    end;
  end;
  mCache := TRuleDerived.Open(AContext);
  mLocal := TRuleDerived.UnitIndex(mCache, AContext);
  mReported := nil;
  for mRoutine in TRuleDerived.Routines(mCache, AContext) do
  begin
    CheckRoutine(mRoutine);
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
  mProp: TDfmProperty;
  mChild: TDfmObject;
  mEvent: TFormEvent;
begin
  if AObject.Kind = TDfmObjectKind.Item then
  begin
    Exit;
  end;
  for mProp in AObject.Properties do
  begin
    if mProp.IsEvent then
    begin
      mEvent := Default(TFormEvent);
      if not AIsRoot then
      begin
        mEvent.Component := AObject.Name;
      end;
      mEvent.Event := mProp.Name;
      mEvent.Handler := mProp.Value;
      mEvent.Owner := AOwner;
      AEvents := AEvents + [mEvent];
    end;
  end;
  for mChild in AObject.Children do
  begin
    CollectEvents(mChild, False, AOwner, AEvents);
  end;
end;

function TInheritedFormHandlerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-form-handler-without-inherited', TRuleSeverity.Warning,
    cTexts[TFormsText.InheritedTitle].Text);
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
  mInherited_: TArray<TFormEvent>;
  mUsedUnits: TArray<string>;

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
    mData: TBytes;
    mFormat_: TFileFormat;
    mText: string;
    mMatch: TMatch;
  begin
    Result := '';
    AUnits := nil;
    if not AContext.ReadFile(ChangeFileExt(AFormFile, '.pas'), mData) then
    begin
      Exit;
    end;
    mText := TFileEncoding.Decode(mData, mFormat_);
    AUnits := TUsesClauses.UsedUnitsOf(mText);
    mMatch := TRegEx.Match(mText, '\b' + AClassName + '\s*=\s*class\s*\(\s*([\w.]+)', [roIgnoreCase]);
    if mMatch.Success then
    begin
      Result := mMatch.Groups[1].Value;
    end;
  end;

  function FindInherited(const AEvent: TFormEvent; out AFound: TFormEvent): Boolean;
  var
    mEvent: TFormEvent;
  begin
    for mEvent in mInherited_ do
    begin
      if SameText(mEvent.Component, AEvent.Component) and SameText(mEvent.Event, AEvent.Event) then
      begin
        AFound := mEvent;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure CollectAncestors(const AClassName: string);
  var
    mParent, mText, mFileName: string;
    mUnits, mMore: TArray<string>;
    mLevel: Integer;
    mParsed: TDfmDocument;
    mIsInherited: Boolean;
    mEvents: TArray<TFormEvent>;
    mEvent, mFound: TFormEvent;
  begin
    mParent := AClassName;
    mUnits := mUsedUnits;
    for mLevel := 1 to 8 do
    begin
      if not AncestorForm(mParent, mUnits, mText, mFileName) then
      begin
        Exit;
      end;
      mParsed := TDfmParser.Parse(mText);
      try
        mEvents := nil;
        CollectEvents(mParsed.Root, True, mParsed.Root.TypeName, mEvents);
        mIsInherited := mParsed.Root.Kind = TDfmObjectKind.Inherited_;
      finally
        mParsed.Free;
      end;
      // Der nächste Vorfahr gewinnt.
      for mEvent in mEvents do
      begin
        if not FindInherited(mEvent, mFound) then
        begin
          mInherited_ := mInherited_ + [mEvent];
        end;
      end;
      if not mIsInherited then
      begin
        Exit;
      end;
      mParent := ParentInFile(Copy(mParent, LastDelimiter('.', mParent) + 1, MaxInt), mFileName, mMore);
      if mParent = '' then
      begin
        Exit;
      end;
      mUnits := mUnits + mMore;
    end;
  end;

  function FindRoutine(const AName: string): TSyntaxNode;
  var
    mRoutine: TSyntaxNode;
  begin
    for mRoutine in TRuleDerived.Routines(TRuleDerived.Open(AContext), AContext) do
    begin
      if SameText(mRoutine.Name, AName) then
      begin
        Exit(mRoutine);
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
      mFixes := [TRuleFix.Create(cTexts[TFormsText.InsertInherited].Text, [TRuleEdit.Create(TTextRange.Create(
        ATokens.BeginToken.EndPos, ATokens.BeginToken.EndPos), mLineBreak +
        TTextLines.IndentOf(AContext.Text, ATokens.BeginToken.StartPos.Line) + '  inherited;')], True)];
    end;
    AReport.Add(TTextRange.Create(ATokens.NameToken.StartPos, ATokens.NameToken.EndPos),
      cTexts[TFormsText.NotExecuted].Fmt([AAncestor.Owner, AAncestor.Handler]),
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
  mUsedUnits := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  mInherited_ := nil;
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
    cTexts[TFormsText.SelfFreeTitle].Text);
end;

/// <summary>Kommt Free, Destroy oder DisposeOf im Text vor?</summary>
function MentionsFree(const AText: string): Boolean;
begin
  Result := ContainsText(AText, 'Free') or ContainsText(AText, 'Destroy') or ContainsText(AText, 'DisposeOf');
end;

procedure TSelfFreeInEventHandlerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mEvents: TArray<TFormEvent>;
  mClassName: string;
  mVariables: TArray<string>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Gibt die Anweisung das Formular selbst frei?
  function FreesSelf(const AStatement: string): Boolean;
  var
    mText, mName: string;
  begin
    mText := LowerCase(StringReplace(StringReplace(StringReplace(AStatement, ' ', '', [rfReplaceAll]), #9, '',
      [rfReplaceAll]), ';', '', [rfReplaceAll]));
    mText := StringReplace(StringReplace(mText, #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]);
    if MatchStr(mText, ['free', 'self.free', 'destroy', 'self.destroy', 'disposeof', 'self.disposeof',
      'freeandnil(self)']) then
    begin
      Exit(True);
    end;
    for mName in mVariables do
    begin
      if MatchStr(mText, [LowerCase(mName) + '.free', LowerCase(mName) + '.destroy', LowerCase(mName) + '.disposeof',
        'freeandnil(' + LowerCase(mName) + ')']) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Ereignis der Formulardatei, das AMethod als Handler hat; '' ohne.
  function EventOf(const AMethod: string): string;
  var
    mEvent: TFormEvent;
  begin
    for mEvent in mEvents do
    begin
      if SameText(mEvent.Handler, AMethod) then
      begin
        Exit(mEvent.Event);
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
    mMethod := Copy(ARoutine.Name, Length(mClassName) + 2, MaxInt);
    if not StartsText(mClassName + '.', ARoutine.Name) or (Pos('.', mMethod) > 0) or (ABody = nil) then
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
    mWhat := cTexts[TFormsText.EventHandler].Text;
    if StartsText('On', AEvent) and (Length(AEvent) > 2) then
    begin
      mWhat := Copy(AEvent, 3, MaxInt) + cTexts[TFormsText.HandlerSuffix].Text;
    end;
    mReplacement := 'Release';
    mTitle := cTexts[TFormsText.FreeToRelease].Text;
    if AIsClose then
    begin
      mReplacement := 'Action := caFree';
      mTitle := cTexts[TFormsText.ReplaceCaFree].Text;
    end;
    AReport.Add(TTextRange.Create(AStatement.StartPos, AStatement.EndPos),
      cTexts[TFormsText.FreesItself].Fmt([mWhat]),
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
      mClassName := mDocument.Root.TypeName;
      for mProp in mDocument.Root.Properties do
      begin
        AIsForm := AIsForm or SameText(mProp.Name, 'ClientWidth') or SameText(mProp.Name, 'ClientHeight');
      end;
      mEvents := nil;
      CollectEvents(mDocument.Root, True, mClassName, mEvents);
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
        SameText(mSymbol.TypeName, mClassName) then
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
  mClassNode := FindClassDecl(AContext.Tree.Root, mClassName);
  if (mClassNode = nil) or not IsFormClass(mClassNode, mIsForm) then
  begin
    Exit;
  end;
  mCache := TRuleDerived.Open(AContext);
  mVariables := FormVariables(mCache);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Forms', cTexts);

end.
