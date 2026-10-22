unit Atlas.Common.Rules.Builtin.Platform;

// Regeln für Annahmen über die Laufzeitumgebung (#909, Runde 67):
//   ui-call-in-console-or-service  ShowMessage, MessageDlg, InputBox usw. in einem Konsolenprogramm, einem
//                                  Windows-Dienst oder einer DLL ohne Formulare (#1060)
//   load-without-encoding          TStrings.LoadFromFile/SaveToFile und TFile.ReadAllText ohne Kodierung:
//                                  ohne BOM gilt die ANSI-Codepage des Rechners (#1061)
// Die Anwendungsart liefert TRuleContext.Application (TWritelnInGuiAppRule.ApplicationKind); eine Unit mit
// einer Klasse, die von TService erbt, gilt auch ohne Projekt als Dienst.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  UiCallInConsoleOrServiceRuleId = 'ui-call-in-console-or-service';
  LoadWithoutEncodingRuleId = 'load-without-encoding';

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

procedure RegisterPlatformRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUiCallInConsoleOrServiceRule.Create);
  ARegistry.Register(TLoadWithoutEncodingRule.Create);
end;

end.
