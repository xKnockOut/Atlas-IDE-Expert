unit Atlas.Common.Rules.Builtin.Platform;

// Regeln für Annahmen über die Laufzeitumgebung (#909, Runde 67):
//   ui-call-in-console-or-service  ShowMessage, MessageDlg, InputBox usw. in einem Konsolenprogramm, einem
//                                  Windows-Dienst oder einer DLL ohne Formulare (#1060)
//   load-without-encoding          TStrings.LoadFromFile/SaveToFile und TFile.ReadAllText ohne Kodierung:
//                                  ohne BOM gilt die ANSI-Codepage des Rechners (#1061)
//   registry-hklm-write            TRegistry mit RootKey HKEY_LOCAL_MACHINE und schreibendem Zugriff (#1062)
//   now-for-elapsed-time           Laufzeit mit Now gemessen statt mit TStopwatch (#1063)
// Die Anwendungsart liefert TRuleContext.Application (TWritelnInGuiAppRule.ApplicationKind); eine Unit mit
// einer Klasse, die von TService erbt, gilt auch ohne Projekt als Dienst.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  UiCallInConsoleOrServiceRuleId = 'ui-call-in-console-or-service';
  LoadWithoutEncodingRuleId = 'load-without-encoding';
  RegistryHklmWriteRuleId = 'registry-hklm-write';
  NowForElapsedTimeRuleId = 'now-for-elapsed-time';

type
  TUiCallInConsoleOrServiceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoadWithoutEncodingRule = class(TInterfacedObject, IRule)
  public const
    DefaultEncoding = 'UTF8';
    /// <summary>Klassen-Properties von TEncoding, die die Option defaultEncoding erlaubt.</summary>
    Encodings: array[0..6] of string = ('UTF8', 'Unicode', 'BigEndianUnicode', 'ANSI', 'ASCII', 'UTF7',
      'Default');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRegistryHklmWriteRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TNowForElapsedTimeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Regeln zur Laufzeitumgebung.</summary>
procedure RegisterPlatformRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Text.Lines;

type
  TTokens = TArray<TPascalToken>;

function NodeText(const AContext: TRuleContext; ANode: TSyntaxNode): string;
begin
  Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Ein Bezeichner oder eine Kette A.B.C, deren letzter Teil AName ist.</summary>
function IsName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    SameText(ANode.Name, AName);
end;

/// <summary>Nur Bezeichner und Punkte: Unit- oder Klassenname vor einer Routine.</summary>
function IsQualifiedName(ANode: TSyntaxNode): Boolean;
begin
  if ANode.Kind = TSyntaxKind.Identifier then
    Exit(True);
  Result := (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and IsQualifiedName(ANode[0]);
end;

/// <summary>Index des ersten Tokens ab AOffset (binäre Suche); Length(ATokens), wenn keiner folgt.</summary>
function TokenAt(const ATokens: TTokens; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

/// <summary>Pfad der bedingten Übersetzung am Anfang von ANode; '' ohne Bedingungen.</summary>
function PathOf(const APaths: TArray<string>; const ATokens: TTokens; ANode: TSyntaxNode): string;
begin
  Result := TConditionalBranches.PathAt(APaths, TokenAt(ATokens, ANode.StartOffset));
end;

procedure CollectNodes(ANode, ARoot: TSyntaxNode; AOwnRoutineOnly: Boolean; AList: TList<TSyntaxNode>);
var
  Index: Integer;
begin
  if AOwnRoutineOnly and (ANode <> ARoot) and (ANode.Kind = TSyntaxKind.RoutineDecl) then
    Exit;
  AList.Add(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    CollectNodes(ANode[Index], ARoot, AOwnRoutineOnly, AList);
end;

/// <summary>ARoot und alle Knoten darunter in Baumreihenfolge (Reihenfolge des Quelltexts). Mit
/// AOwnRoutineOnly ohne lokale Routinen; die prüft jede Regel für sich.</summary>
function NodesOf(ARoot: TSyntaxNode; AOwnRoutineOnly: Boolean): TArray<TSyntaxNode>;
var
  List: TList<TSyntaxNode>;
begin
  List := TList<TSyntaxNode>.Create;
  try
    CollectNodes(ARoot, ARoot, AOwnRoutineOnly, List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

/// <summary>Namen der Routinen, die die Datei selbst deklariert (letzter Teil von TKlasse.Name).</summary>
function DeclaredRoutines(ARoot: TSyntaxNode): TArray<string>;
var
  Node: TSyntaxNode;
  Name: string;
begin
  Result := nil;
  for Node in NodesOf(ARoot, False) do
    if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader] then
    begin
      Name := Node.Name;
      if Pos('.', Name) > 0 then
        Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
      Result := Result + [Name];
    end;
end;

/// <summary>Kommt ein Bezeichner AName in ANode oder darunter vor?</summary>
function Mentions(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if Mentions(ANode[Index], AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Edit, das AUnitName ins uses einträgt, wenn die Unit (auch ohne Namespace) fehlt.</summary>
function UsesEdit(const AContext: TRuleContext; const ATokens: TTokens; AOffset: Integer;
  const AUnitName: string; out AEdit: TTextEdit): Boolean;
var
  Used: TArray<string>;
  Short: string;
begin
  Used := TUsesClauses.UsedUnits(ATokens);
  Short := Copy(AUnitName, LastDelimiter('.', AUnitName) + 1, MaxInt);
  if TUsesClauses.IsUsed(Used, AUnitName, AContext.Namespaces) or TUsesClauses.IsUsed(Used, Short, nil) then
    Exit(False);
  Result := TUsesClauses.AddUnit(ATokens, AOffset, AUnitName, TTextLines.LineBreakOf(AContext.Text), AEdit);
end;

{ TUiCallInConsoleOrServiceRule }

const
  // Routinen aus Vcl.Dialogs und FMX.Dialogs, die ein modales Fenster zeigen.
  DialogRoutines: array[0..9] of string = ('ShowMessage', 'ShowMessageFmt', 'ShowMessagePos', 'MessageDlg',
    'MessageDlgPos', 'MessageDlgPosHelp', 'TaskMessageDlg', 'TaskMessageDlgPos', 'InputBox', 'InputQuery');
  // Klassenmethoden von FMX.DialogService.
  DialogServices: array[0..2] of string = ('TDialogService', 'TDialogServiceSync', 'TDialogServiceAsync');
  DialogServiceMethods: array[0..3] of string = ('ShowMessage', 'MessageDialog', 'InputQuery', 'InputBox');

function TUiCallInConsoleOrServiceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UiCallInConsoleOrServiceRuleId, TRuleSeverity.Warning,
    'Dialog in Konsolenprogramm oder Dienst');
end;

procedure TUiCallInConsoleOrServiceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Kind: TRuleApplicationKind;
  Declared: TArray<string>;
  Place, Advice: string;
  Confidence: TRuleConfidence;

  // Eine Klasse der Datei erbt (auch über Vorfahren im Index) von TService.
  function DeclaresService: Boolean;
  var
    Cache: IRuleDerivedCache;
    Local: TUnitIndex;
    Ancestry: TAncestry;
    Symbol: TIndexSymbol;
  begin
    Result := False;
    Cache := TRuleDerived.Open(AContext);
    Local := TRuleDerived.UnitIndex(Cache, AContext);
    Ancestry := TAncestry.Create(AContext.Index, Local);
    try
      for Symbol in Local.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.ClassType) and Ancestry.DescendsFrom(Symbol.Name, 'TService') then
          Exit(True);
    finally
      Ancestry.Free;
    end;
  end;

  // "if IsConsole then" bzw. "if not IsConsole then" zeigt, dass der Aufruf bedacht ist.
  function Guarded(ANode: TSyntaxNode): Boolean;
  var
    Parent: TSyntaxNode;
  begin
    Parent := ANode.Parent;
    while Parent <> nil do
    begin
      if (Parent.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement]) and (Parent.ChildCount > 0) and
        Mentions(Parent[0], 'IsConsole') then
        Exit(True);
      Parent := Parent.Parent;
    end;
    Result := False;
  end;

  // Zeigt der Aufruf ein Fenster? ACallee ist das erste Kind des Call-Knotens.
  function IsDialog(ACallee: TSyntaxNode): Boolean;
  begin
    if ACallee.Kind = TSyntaxKind.Identifier then
      Exit(MatchText(ACallee.Name, DialogRoutines) and not MatchText(ACallee.Name, Declared));
    Result := False;
    if (ACallee.Kind <> TSyntaxKind.MemberAccess) or (ACallee.ChildCount <> 1) then
      Exit;
    // Vcl.Dialogs.ShowMessage, Dialogs.MessageDlg
    if MatchText(ACallee.Name, DialogRoutines) and IsQualifiedName(ACallee[0]) and
      IsName(ACallee[0], 'Dialogs') then
      Exit(True);
    // Application.MessageBox, auch Vcl.Forms.Application.MessageBox
    if SameText(ACallee.Name, 'MessageBox') and IsQualifiedName(ACallee[0]) and IsName(ACallee[0], 'Application') then
      Exit(True);
    // TDialogService.ShowMessage
    Result := MatchText(ACallee.Name, DialogServiceMethods) and IsQualifiedName(ACallee[0]) and
      MatchText(ACallee[0].Name, DialogServices);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Callee: TSyntaxNode;
  begin
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
    begin
      Callee := ANode[0];
      if IsDialog(Callee) and not Guarded(ANode) then
        AReport.Add(NodeRange(Callee), Format('%s %s %s', [NodeText(AContext, Callee), Place, Advice]),
          Confidence);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Kind := AContext.Application;
  // Ohne Projekt nur die .dpr selbst.
  if Kind = TRuleApplicationKind.Unknown then
    Kind := TWritelnInGuiAppRule.ApplicationKind('', AContext.Text);
  Confidence := TRuleConfidence.High;
  Advice := 'protokollieren statt anzeigen.';
  if (Kind = TRuleApplicationKind.Service) or DeclaresService then
    Place := 'in einem Windows-Dienst blockiert unsichtbar;'
  // Units mit Formular zeigen Fenster bewusst, auch in einem Konsolenprogramm oder einer DLL.
  else if AContext.FormText <> '' then
    Exit
  else if Kind = TRuleApplicationKind.Console then
    Place := 'in einem Konsolenprogramm wartet auf einen Klick, wenn das Programm unbeaufsichtigt läuft;'
  else if Kind = TRuleApplicationKind.Library_ then
  begin
    // Ob der Host eine Oberfläche hat, weiß nur das aufrufende Programm.
    Confidence := TRuleConfidence.Medium;
    Place := 'in einer DLL ohne Formulare blockiert, wenn der Host keine Oberfläche hat (Dienst, Webserver);';
    Advice := 'protokollieren oder einen Fehler zurückgeben.';
  end
  else
    Exit;
  Declared := DeclaredRoutines(AContext.Tree.Root);
  Visit(AContext.Tree.Root);
end;

{ TLoadWithoutEncodingRule }

const
  TextFileMethods: array[0..3] of string = ('LoadFromFile', 'SaveToFile', 'LoadFromStream', 'SaveToStream');
  // Typen, deren LoadFromFile/SaveToFile Text mit TEncoding lesen bzw. schreiben.
  StringListTypes: array[0..5] of string = ('TStrings', 'TStringList', 'THashedStringList', 'TMemoStrings',
    'TRichEditStrings', 'TAnsiStringList');
  // Properties der VCL- und FireDAC-Komponenten vom Typ TStrings.
  StringListProperties: array[0..3] of string = ('Lines', 'Items', 'SQL', 'Strings');
  // TFile-Methoden, die ohne BOM TEncoding.Default lesen; WriteAllText und TStreamReader nehmen UTF-8.
  ReadAllMethods: array[0..1] of string = ('ReadAllText', 'ReadAllLines');

function TLoadWithoutEncodingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LoadWithoutEncodingRuleId, TRuleSeverity.Warning,
    'Text laden oder speichern ohne Kodierung');
end;

procedure TLoadWithoutEncodingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Types: TDeclaredTypes;
  Tokens: TTokens;
  Encoding: string;

  // Empfänger von LoadFromFile ist sicher eine Stringliste.
  function IsStringList(AReceiver: TSyntaxNode): Boolean;
  var
    TypeName: string;
  begin
    case AReceiver.Kind of
      TSyntaxKind.Identifier:
        begin
          TypeName := Types.DeclaredType(AReceiver.Name, AReceiver.StartPos);
          Result := MatchText(TypeName, StringListTypes);
        end;
      TSyntaxKind.MemberAccess:
        Result := MatchText(AReceiver.Name, StringListProperties);
    else
      Result := False;
    end;
  end;

  function RoutineOf(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
      Result := Result.Parent;
  end;

  // Empfänger.DefaultEncoding := … in der Datei oder Laden mit Kodierung vor ACall in derselben Routine.
  function EncodingKnown(ACall: TSyntaxNode; const AReceiver: string): Boolean;
  var
    Node, Routine: TSyntaxNode;
  begin
    for Node in NodesOf(AContext.Tree.Root, False) do
      if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
        (Node[0].Kind = TSyntaxKind.MemberAccess) and SameText(Node[0].Name, 'DefaultEncoding') and
        (Node[0].ChildCount = 1) and SameText(NodeText(AContext, Node[0][0]), AReceiver) then
        Exit(True);
    Routine := RoutineOf(ACall);
    if Routine <> nil then
      // LoadFromFile(Datei, Kodierung) merkt sich die Kodierung für SaveToFile.
      for Node in NodesOf(Routine, True) do
        if (Node.Kind = TSyntaxKind.Call) and (Node.StartOffset < ACall.StartOffset) and (Node.ChildCount = 3) and
          (Node[0].Kind = TSyntaxKind.MemberAccess) and StartsText('LoadFrom', Node[0].Name) and
          (Node[0].ChildCount = 1) and SameText(NodeText(AContext, Node[0][0]), AReceiver) then
          Exit(True);
    Result := False;
  end;

  function Fix(ACall: TSyntaxNode): TArray<TRuleFix>;
  var
    Last: TSyntaxNode;
    Edits: TArray<TRuleEdit>;
    Extra: TTextEdit;
  begin
    Last := ACall[ACall.ChildCount - 1];
    Edits := [TRuleEdit.Create(TTextRange.Create(Last.EndPos, Last.EndPos), ', TEncoding.' + Encoding)];
    if UsesEdit(AContext, Tokens, ACall.StartOffset, 'System.SysUtils', Extra) then
      Edits := Edits + [Extra];
    Result := [TRuleFix.Create(Format('TEncoding.%s ergänzen', [Encoding]), Edits)];
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    Callee: TSyntaxNode;
    Method, Receiver: string;
  begin
    Callee := ACall[0];
    if (Callee.Kind <> TSyntaxKind.MemberAccess) or (Callee.ChildCount <> 1) or (ACall.ChildCount <> 2) then
      Exit;
    Method := Callee.Name;
    if MatchText(Method, ReadAllMethods) and IsQualifiedName(Callee[0]) and IsName(Callee[0], 'TFile') then
    begin
      AReport.Add(NodeRange(Callee), Format('TFile.%s ohne Kodierung liest Dateien ohne BOM mit der ' +
        'ANSI-Codepage.', [Method]), TRuleConfidence.Medium, Fix(ACall));
      Exit;
    end;
    if not MatchText(Method, TextFileMethods) or not IsStringList(Callee[0]) then
      Exit;
    Receiver := NodeText(AContext, Callee[0]);
    if StartsText('Load', Method) then
    begin
      if not EncodingKnown(ACall, Receiver) then
        AReport.Add(NodeRange(Callee), Format('%s ohne Kodierung liest Dateien ohne BOM mit der ANSI-Codepage.',
          [Method]), TRuleConfidence.Medium, Fix(ACall));
    end
    else if not EncodingKnown(ACall, Receiver) then
      AReport.Add(NodeRange(Callee), Format('%s ohne Kodierung schreibt mit der ANSI-Codepage; Umlaute gehen ' +
        'auf anderen Rechnern verloren.', [Method]), TRuleConfidence.Medium, Fix(ACall));
  end;

var
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Encoding := TRuleOptions.Text(AContext.Options, 'defaultEncoding', DefaultEncoding);
  if IndexText(Encoding, Encodings) < 0 then
    Encoding := DefaultEncoding
  else
    Encoding := Encodings[IndexText(Encoding, Encodings)];
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Node in NodesOf(AContext.Tree.Root, False) do
      if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) then
        CheckCall(Node);
  finally
    Types.Free;
  end;
end;

{ TRegistryHklmWriteRule }

const
  // Methoden von TRegistry, die schreiben; OpenKey nur mit CanCreate = True.
  RegistryWrites: array[0..16] of string = ('CreateKey', 'DeleteKey', 'DeleteValue', 'RenameValue', 'MoveKey',
    'WriteString', 'WriteExpandString', 'WriteInteger', 'WriteBool', 'WriteFloat', 'WriteCurrency', 'WriteDate',
    'WriteTime', 'WriteDateTime', 'WriteBinaryData', 'SaveKey', 'RestoreKey');

function TRegistryHklmWriteRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(RegistryHklmWriteRuleId, TRuleSeverity.Hint, 'Schreiben nach HKEY_LOCAL_MACHINE');
end;

procedure TRegistryHklmWriteRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Paths: TArray<string>;

  function IsRootKeyAssign(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and SameText(ANode[0].Name, 'RootKey') and
      (ANode[0].ChildCount = 1);
  end;

  // Reg.WriteString(…), Reg.OpenKey(…, True): Empfänger als Text, sonst ''.
  function WriteReceiver(ANode: TSyntaxNode): string;
  var
    Callee: TSyntaxNode;
  begin
    Result := '';
    if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount = 0) then
      Exit;
    Callee := ANode[0];
    if (Callee.Kind <> TSyntaxKind.MemberAccess) or (Callee.ChildCount <> 1) then
      Exit;
    if MatchText(Callee.Name, RegistryWrites) or (SameText(Callee.Name, 'OpenKey') and (ANode.ChildCount = 3) and
      IsName(ANode[2], 'True')) then
      Result := NodeText(AContext, Callee[0]);
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Events: TArray<TSyntaxNode>;
    Index, Later: Integer;
    Assign, Event: TSyntaxNode;
    Receiver: string;
    Written: Boolean;
  begin
    // Zuweisungen an RootKey und schreibende Aufrufe in Reihenfolge des Quelltexts.
    Events := nil;
    // Lokale Routinen prüft CheckRoutine für sich.
    for Event in NodesOf(ARoutine, True) do
      if IsRootKeyAssign(Event) or (WriteReceiver(Event) <> '') then
        Events := Events + [Event];
    for Index := 0 to High(Events) do
    begin
      Assign := Events[Index];
      if not IsRootKeyAssign(Assign) or not IsName(Assign[1], 'HKEY_LOCAL_MACHINE') then
        Continue;
      Receiver := NodeText(AContext, Assign[0][0]);
      Written := False;
      for Later := Index + 1 to High(Events) do
      begin
        Event := Events[Later];
        // Ein neuer RootKey, der immer mit dieser Zuweisung übersetzt wird, gilt für alles danach.
        if IsRootKeyAssign(Event) then
        begin
          if SameText(NodeText(AContext, Event[0][0]), Receiver) and
            TConditionalBranches.Implies(PathOf(Paths, Tokens, Event), PathOf(Paths, Tokens, Assign)) then
            Break;
        end
        else if SameText(WriteReceiver(Event), Receiver) and
          not TConditionalBranches.Exclusive(PathOf(Paths, Tokens, Event), PathOf(Paths, Tokens, Assign)) then
        begin
          Written := True;
          Break;
        end;
      end;
      if Written then
        AReport.Add(NodeRange(Assign[1]), 'Schreiben nach HKEY_LOCAL_MACHINE braucht Administratorrechte; ' +
          'ohne sie schlägt es fehl oder landet in der Virtualisierung.', TRuleConfidence.High,
          [TRuleFix.Create('HKEY_CURRENT_USER verwenden', [TRuleEdit.Create(NodeRange(Assign[1]),
          'HKEY_CURRENT_USER')])]);
    end;
  end;

var
  Routine: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  for Routine in TRuleDerived.Routines(TRuleDerived.Open(AContext), AContext) do
    CheckRoutine(Routine);
end;

{ TNowForElapsedTimeRule }

const
  // DateUtils-Funktionen, die den Abstand zweier Zeitpunkte liefern.
  BetweenFunctions: array[0..9] of string = ('MilliSecondsBetween', 'SecondsBetween', 'MinutesBetween',
    'HoursBetween', 'MilliSecondSpan', 'SecondSpan', 'MinuteSpan', 'HourSpan', 'DaysBetween', 'DaySpan');
  // Die Korrektur ersetzt nur diese, mit dem passenden Teiler für ElapsedMilliseconds.
  StopwatchFunctions: array[0..2] of string = ('MilliSecondsBetween', 'SecondsBetween', 'MinutesBetween');
  StopwatchDivisors: array[0..2] of string = ('', ' div 1000', ' div 60000');

type
  /// <summary>Zuweisung "Start := Now" bzw. "var Start := Now" in einer Routine.</summary>
  TNowStart = record
    Name: string;
    Node: TSyntaxNode;
  end;

function TNowForElapsedTimeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(NowForElapsedTimeRuleId, TRuleSeverity.Hint, 'Laufzeit mit Now gemessen');
end;

procedure TNowForElapsedTimeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Paths: TArray<string>;

  // Now, Now() oder SysUtils.Now
  function IsNow(ANode: TSyntaxNode): Boolean;
  begin
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 1) then
      ANode := ANode[0];
    Result := IsName(ANode, 'Now') and IsQualifiedName(ANode);
  end;

  function InsideAny(AOffset: Integer; const ANodes: TArray<TSyntaxNode>): Boolean;
  var
    Node: TSyntaxNode;
  begin
    for Node in ANodes do
      if (AOffset >= Node.StartOffset) and (AOffset < Node.EndOffset) then
        Exit(True);
    Result := False;
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Starts: TArray<TNowStart>;
    Measures: TArray<TSyntaxNode>;
    Index, Start: Integer;
    Found: TArray<TRuleFix>;
    Node: TSyntaxNode;
    Item: TNowStart;

    // Variable AName, der vor AAt in einem nicht ausschließenden Zweig Now zugewiesen wurde: Index, sonst -1.
    function StartOf(ANode, AAt: TSyntaxNode): Integer;
    var
      Item: Integer;
    begin
      Result := -1;
      if ANode.Kind <> TSyntaxKind.Identifier then
        Exit;
      for Item := 0 to High(Starts) do
        if SameText(Starts[Item].Name, ANode.Name) and (Starts[Item].Node.StartOffset < AAt.StartOffset) and
          not TConditionalBranches.Exclusive(PathOf(Paths, Tokens, Starts[Item].Node), PathOf(Paths, Tokens, AAt)) then
          Result := Item;
    end;

    // Now - Start, Ende - Start, MilliSecondsBetween(Now, Start): Index des Starts, sonst -1.
    function MeasuredStart(ANode: TSyntaxNode): Integer;
    var
      A, B: TSyntaxNode;
    begin
      Result := -1;
      if (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '-') and (ANode.ChildCount = 2) then
      begin
        A := ANode[0];
        B := ANode[1];
      end
      else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 3) and IsQualifiedName(ANode[0]) and
        MatchText(ANode[0].Name, BetweenFunctions) then
      begin
        A := ANode[1];
        B := ANode[2];
      end
      else
        Exit;
      if IsNow(A) or (StartOf(A, ANode) >= 0) then
        Result := StartOf(B, ANode);
      if (Result < 0) and (IsNow(B) or (StartOf(B, ANode) >= 0)) then
        Result := StartOf(A, ANode);
    end;

    // Korrektur nur, wenn Start eine lokale TDateTime-Variable allein für Messungen wie
    // MilliSecondsBetween(Now, Start) ist.
    function Fixes(AStart: Integer): TArray<TRuleFix>;
    var
      Decl, TypeNode, Use, Value, Node: TSyntaxNode;
      Measured: TArray<TSyntaxNode>;
      Edits: TArray<TRuleEdit>;
      Extra: TTextEdit;
      Name, NewName: string;
      Item: Integer;
      Clean: Boolean;
    begin
      Result := nil;
      Name := Starts[AStart].Name;
      for Item := 0 to High(Starts) do
        if (Item <> AStart) and SameText(Starts[Item].Name, Name) then
          Exit;
      Decl := nil;
      for Node in NodesOf(ARoutine, True) do
        if (Node.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar]) and SameText(Node.Name, Name) then
          Decl := Node;
      if Decl = nil then
        Exit;
      TypeNode := Decl.FindChild(TSyntaxKind.TypeReference);
      if (TypeNode <> nil) and not SameText(TypeNode.Name, 'TDateTime') then
        Exit;
      if (Decl.Kind = TSyntaxKind.VarDecl) and (TypeNode = nil) then
        Exit;
      if (Decl.Kind = TSyntaxKind.InlineVar) and (Decl <> Starts[AStart].Node) then
        Exit;
      // Jede andere Erwähnung muss eine Messung sein, die sich umschreiben lässt.
      Measured := nil;
      Clean := True;
      for Node in NodesOf(ARoutine, True) do
      begin
        if InsideAny(Node.StartOffset, Measured) then
          Continue;
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount = 3) and IsQualifiedName(Node[0]) and
          (IndexText(Node[0].Name, StopwatchFunctions) >= 0) and IsNow(Node[1]) and
          (Node[2].Kind = TSyntaxKind.Identifier) and SameText(Node[2].Name, Name) then
          Measured := Measured + [Node]
        else if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, Name) and
          not ((Node.Parent = Starts[AStart].Node) and (Node.Parent[0] = Node)) then
          Clean := False;
      end;
      if not Clean or (Measured = nil) then
        Exit;
      // Wie im Issue heißt Start danach Uhr, wenn der Name in der Datei frei ist.
      NewName := 'Uhr';
      for Item := 0 to High(Tokens) do
        if (Tokens[Item].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Item].Text, NewName) then
          NewName := Name;
      Edits := nil;
      if TypeNode <> nil then
        Edits := Edits + [TRuleEdit.Create(NodeRange(TypeNode), 'TStopwatch')];
      Value := Starts[AStart].Node[Starts[AStart].Node.ChildCount - 1];
      Edits := Edits + [TRuleEdit.Create(NodeRange(Value), 'TStopwatch.StartNew')];
      for Use in Measured do
        Edits := Edits + [TRuleEdit.Create(NodeRange(Use), NewName + '.ElapsedMilliseconds' +
          StopwatchDivisors[IndexText(Use[0].Name, StopwatchFunctions)])];
      if not SameText(NewName, Name) then
        for Item := TokenAt(Tokens, ARoutine.StartOffset) to High(Tokens) do
        begin
          if Tokens[Item].Offset >= ARoutine.EndOffset then
            Break;
          if (Tokens[Item].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Item].Text, Name) and
            not InsideAny(Tokens[Item].Offset, Measured) then
            Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Tokens[Item].StartPos, Tokens[Item].EndPos),
              NewName)];
        end;
      if UsesEdit(AContext, Tokens, ARoutine.StartOffset, 'System.Diagnostics', Extra) then
        Edits := Edits + [Extra];
      Result := [TRuleFix.Create('In TStopwatch umwandeln', Edits)];
    end;

  begin
    Starts := nil;
    Measures := nil;
    for Node in NodesOf(ARoutine, True) do
      if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
        (Node[0].Kind = TSyntaxKind.Identifier) and IsNow(Node[1]) then
      begin
        Item.Name := Node[0].Name;
        Item.Node := Node;
        Starts := Starts + [Item];
      end
      else if (Node.Kind = TSyntaxKind.InlineVar) and (Pos(',', Node.Name) = 0) and (Node.ChildCount > 0) and
        IsNow(Node[Node.ChildCount - 1]) then
      begin
        Item.Name := Node.Name;
        Item.Node := Node;
        Starts := Starts + [Item];
      end;
    if Starts = nil then
      Exit;
    // Teilausdrücke einer Messung nicht noch einmal melden.
    for Node in NodesOf(ARoutine, True) do
      if not InsideAny(Node.StartOffset, Measures) and (MeasuredStart(Node) >= 0) then
        Measures := Measures + [Node];
    for Index := 0 to High(Measures) do
    begin
      Start := MeasuredStart(Measures[Index]);
      Found := Fixes(Start);
      AReport.Add(NodeRange(Measures[Index]), 'Laufzeit mit Now gemessen; TStopwatch ist genauer und unabhängig ' +
        'von der Uhrzeit.', TRuleConfidence.High, Found);
    end;
  end;

var
  Routine: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  for Routine in TRuleDerived.Routines(TRuleDerived.Open(AContext), AContext) do
    CheckRoutine(Routine);
end;

procedure RegisterPlatformRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUiCallInConsoleOrServiceRule.Create);
  ARegistry.Register(TLoadWithoutEncodingRule.Create);
  ARegistry.Register(TRegistryHklmWriteRule.Create);
  ARegistry.Register(TNowForElapsedTimeRule.Create);
end;

end.
