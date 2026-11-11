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
  cUiCallInConsoleOrServiceRuleId = 'ui-call-in-console-or-service';
  cLoadWithoutEncodingRuleId = 'load-without-encoding';
  cRegistryHklmWriteRuleId = 'registry-hklm-write';
  cNowForElapsedTimeRuleId = 'now-for-elapsed-time';

type
  TUiCallInConsoleOrServiceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoadWithoutEncodingRule = class(TInterfacedObject, IRule)
  public const
    cDefaultEncoding = 'UTF8';
    /// <summary>Klassen-Properties von TEncoding, die die Option defaultEncoding erlaubt.</summary>
    cEncodings: array[0..6] of string = ('UTF8', 'Unicode', 'BigEndianUnicode', 'ANSI', 'ASCII', 'UTF7',
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
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TPlatformText = (DialogTitle, LogInstead, InService, InConsole, InDll, LogOrError, EncodingTitle, AddEncoding,
    FileNoEncoding, ReadNoEncoding, WriteNoEncoding, HklmTitle, Hklm, UseHkcu, NowMeasure, ToStopwatch, NowTitle);

const
  cTexts: array[TPlatformText] of TAtlasText = (
    (De: 'Dialog in Konsolenprogramm oder Dienst'; En: 'Dialog in console program or service'),
    (De: 'protokollieren statt anzeigen.'; En: 'log instead of displaying.'),
    (De: 'in einem Windows-Dienst blockiert unsichtbar;'; En: 'in a Windows service blocks invisibly;'),
    (De: 'in einem Konsolenprogramm wartet auf einen Klick, wenn das Programm unbeaufsichtigt läuft;';
     En: 'in a console program waits for a click when the program runs unattended;'),
    (De: 'in einer DLL ohne Formulare blockiert, wenn der Host keine Oberfläche hat (Dienst, Webserver);';
     En: 'in a DLL without forms blocks when the host has no user interface (service, web server);'),
    (De: 'protokollieren oder einen Fehler zurückgeben.'; En: 'log or return an error.'),
    (De: 'Text laden oder speichern ohne Kodierung'; En: 'Loading or saving text without encoding'),
    (De: 'TEncoding.%s ergänzen'; En: 'Add TEncoding.%s'),
    (De: 'TFile.%s ohne Kodierung liest Dateien ohne BOM mit der ANSI-Codepage.';
     En: 'TFile.%s without encoding reads files without BOM with the ANSI code page.'),
    (De: '%s ohne Kodierung liest Dateien ohne BOM mit der ANSI-Codepage.';
     En: '%s without encoding reads files without BOM with the ANSI code page.'),
    (De: '%s ohne Kodierung schreibt mit der ANSI-Codepage; Umlaute gehen auf anderen Rechnern verloren.';
     En: '%s without encoding writes with the ANSI code page; umlauts get lost on other computers.'),
    (De: 'Schreiben nach HKEY_LOCAL_MACHINE'; En: 'Writing to HKEY_LOCAL_MACHINE'),
    (De: 'Schreiben nach HKEY_LOCAL_MACHINE braucht Administratorrechte; ohne sie schlägt es fehl oder landet in der ' +
      'Virtualisierung.';
     En: 'Writing to HKEY_LOCAL_MACHINE needs administrator rights; without them it fails or ends up in ' +
      'virtualization.'),
    (De: 'HKEY_CURRENT_USER verwenden'; En: 'Use HKEY_CURRENT_USER'),
    (De: 'Laufzeit mit Now gemessen; TStopwatch ist genauer und unabhängig von der Uhrzeit.';
     En: 'Run time measured with Now; TStopwatch is more precise and independent of the time of day.'),
    (De: 'In TStopwatch umwandeln'; En: 'Convert to TStopwatch'),
    (De: 'Laufzeit mit Now gemessen'; En: 'Run time measured with Now'));

{$SCOPEDENUMS OFF}

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

/// <summary>Nur Bezeichner und Punkte: Unit- oder Klassenname vor einer Routine. Iterativ (tiefe Bäume sprengen den
/// Stapel nicht).
/// </summary>
function IsQualifiedName(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode;
  while (mNode.Kind = TSyntaxKind.MemberAccess) and (mNode.ChildCount = 1) do
  begin
    mNode := mNode[0];
  end;
  Result := mNode.Kind = TSyntaxKind.Identifier;
end;

/// <summary>Pfad der bedingten Übersetzung am Anfang von ANode; '' ohne Bedingungen.</summary>
function PathOf(const APaths: TArray<string>; const ATokens: TTokens; ANode: TSyntaxNode): string;
begin
  Result := TConditionalBranches.PathAt(APaths, TokenFrom(ATokens, ANode.StartOffset));
end;

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
procedure CollectNodes(ARoot: TSyntaxNode; AOwnRoutineOnly: Boolean; AList: TList<TSyntaxNode>);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if AOwnRoutineOnly and (mNode <> ARoot) and (mNode.Kind = TSyntaxKind.RoutineDecl) then
      begin
        Continue;
      end;
      AList.Add(mNode);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>ARoot und alle Knoten darunter in Baumreihenfolge (Reihenfolge des Quelltexts). Mit
/// AOwnRoutineOnly ohne lokale Routinen; die prüft jede Regel für sich.</summary>
function NodesOf(ARoot: TSyntaxNode; AOwnRoutineOnly: Boolean): TArray<TSyntaxNode>;
var
  mList: TList<TSyntaxNode>;
begin
  mList := TList<TSyntaxNode>.Create;
  try
    CollectNodes(ARoot, AOwnRoutineOnly, mList);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Namen der Routinen, die die Datei selbst deklariert (letzter Teil von TKlasse.Name).</summary>
function DeclaredRoutines(ARoot: TSyntaxNode): TArray<string>;
var
  mNode: TSyntaxNode;
  mName: string;
begin
  Result := nil;
  for mNode in NodesOf(ARoot, False) do
  begin
    if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader] then
    begin
      mName := mNode.Name;
      if Pos('.', mName) > 0 then
      begin
        mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
      end;
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Kommt ein Bezeichner AName in ANode oder darunter vor? Iterativ (tiefe Bäume sprengen den Stapel
/// nicht).</summary>
function Mentions(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, AName) then
      begin
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Edit, das AUnitName ins uses einträgt, wenn die Unit (auch ohne Namespace) fehlt.</summary>
function UsesEdit(const AContext: TRuleContext; const ATokens: TTokens; AOffset: Integer;
  const AUnitName: string; out AEdit: TTextEdit): Boolean;
var
  mUsed: TArray<string>;
  mShort: string;
begin
  mUsed := TUsesClauses.UsedUnits(ATokens);
  mShort := Copy(AUnitName, LastDelimiter('.', AUnitName) + 1, MaxInt);
  if TUsesClauses.IsUsed(mUsed, AUnitName, AContext.Namespaces) or TUsesClauses.IsUsed(mUsed, mShort, nil) then
  begin
    Exit(False);
  end;
  Result := TUsesClauses.AddUnit(ATokens, AOffset, AUnitName, TTextLines.LineBreakOf(AContext.Text), AEdit);
end;

{ TUiCallInConsoleOrServiceRule }

const
  // Routinen aus Vcl.Dialogs und FMX.Dialogs, die ein modales Fenster zeigen.
  cDialogRoutines: array[0..9] of string = ('ShowMessage', 'ShowMessageFmt', 'ShowMessagePos', 'MessageDlg',
    'MessageDlgPos', 'MessageDlgPosHelp', 'TaskMessageDlg', 'TaskMessageDlgPos', 'InputBox', 'InputQuery');
  // Klassenmethoden von FMX.DialogService.
  cDialogServices: array[0..2] of string = ('TDialogService', 'TDialogServiceSync', 'TDialogServiceAsync');
  cDialogServiceMethods: array[0..3] of string = ('ShowMessage', 'MessageDialog', 'InputQuery', 'InputBox');

function TUiCallInConsoleOrServiceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cUiCallInConsoleOrServiceRuleId, TRuleSeverity.Warning,
    cTexts[TPlatformText.DialogTitle].Text);
end;

procedure TUiCallInConsoleOrServiceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mKind: TRuleApplicationKind;
  mDeclared: TArray<string>;
  mPlace, mAdvice: string;
  mConfidence: TRuleConfidence;

  // Eine Klasse der Datei erbt (auch über Vorfahren im Index) von TService.
  function DeclaresService: Boolean;
  var
    mCache: IRuleDerivedCache;
    mLocal: TUnitIndex;
    mAncestry: TAncestry;
    mSymbol: TIndexSymbol;
  begin
    Result := False;
    mCache := TRuleDerived.Open(AContext);
    mLocal := TRuleDerived.UnitIndex(mCache, AContext);
    mAncestry := TAncestry.Create(AContext.Index, mLocal);
    try
      for mSymbol in mLocal.Symbols do
      begin
        if (mSymbol.Kind = TIndexSymbolKind.ClassType) and mAncestry.DescendsFrom(mSymbol.Name, 'TService') then
        begin
          Exit(True);
        end;
      end;
    finally
      mAncestry.Free;
    end;
  end;

  // "if IsConsole then" bzw. "if not IsConsole then" zeigt, dass der Aufruf bedacht ist.
  function Guarded(ANode: TSyntaxNode): Boolean;
  var
    mParent: TSyntaxNode;
  begin
    mParent := ANode.Parent;
    while mParent <> nil do
    begin
      if (mParent.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement]) and (mParent.ChildCount > 0) and
        Mentions(mParent[0], 'IsConsole') then
      begin
        Exit(True);
      end;
      mParent := mParent.Parent;
    end;
    Result := False;
  end;

  // Zeigt der Aufruf ein Fenster? ACallee ist das erste Kind des Call-Knotens.
  function IsDialog(ACallee: TSyntaxNode): Boolean;
  begin
    if ACallee.Kind = TSyntaxKind.Identifier then
    begin
      Exit(MatchText(ACallee.Name, cDialogRoutines) and not MatchText(ACallee.Name, mDeclared));
    end;
    Result := False;
    if (ACallee.Kind <> TSyntaxKind.MemberAccess) or (ACallee.ChildCount <> 1) then
    begin
      Exit;
    end;
    // Vcl.Dialogs.ShowMessage, Dialogs.MessageDlg
    if MatchText(ACallee.Name, cDialogRoutines) and IsQualifiedName(ACallee[0]) and
      IsName(ACallee[0], 'Dialogs') then
    begin
      Exit(True);
    end;
    // Application.MessageBox, auch Vcl.Forms.Application.MessageBox
    if SameText(ACallee.Name, 'MessageBox') and IsQualifiedName(ACallee[0]) and IsName(ACallee[0], 'Application') then
    begin
      Exit(True);
    end;
    // TDialogService.ShowMessage
    Result := MatchText(ACallee.Name, cDialogServiceMethods) and IsQualifiedName(ACallee[0]) and
      MatchText(ACallee[0].Name, cDialogServices);
  end;

  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mCallee: TSyntaxNode;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) then
        begin
          mCallee := mNode[0];
          if IsDialog(mCallee) and not Guarded(mNode) then
          begin
            AReport.Add(NodeRange(mCallee), Format('%s %s %s', [NodeText(AContext, mCallee), mPlace, mAdvice]),
              mConfidence);
          end;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mKind := AContext.Application;
  // Ohne Projekt nur die .dpr selbst.
  if mKind = TRuleApplicationKind.Unknown then
  begin
    mKind := TWritelnInGuiAppRule.ApplicationKind('', AContext.Text);
  end;
  mConfidence := TRuleConfidence.High;
  mAdvice := cTexts[TPlatformText.LogInstead].Text;
  if (mKind = TRuleApplicationKind.Service) or DeclaresService then
  begin
    mPlace := cTexts[TPlatformText.InService].Text;
  end
  // Units mit Formular zeigen Fenster bewusst, auch in einem Konsolenprogramm oder einer DLL.
  else if AContext.FormText <> '' then
  begin
    Exit;
  end
  else if mKind = TRuleApplicationKind.Console then
  begin
    mPlace := cTexts[TPlatformText.InConsole].Text;
  end
  else if mKind = TRuleApplicationKind.Library_ then
  begin
    // Ob der Host eine Oberfläche hat, weiß nur das aufrufende Programm.
    mConfidence := TRuleConfidence.Medium;
    mPlace := cTexts[TPlatformText.InDll].Text;
    mAdvice := cTexts[TPlatformText.LogOrError].Text;
  end
  else
  begin
    Exit;
  end;
  mDeclared := DeclaredRoutines(AContext.Tree.Root);
  Visit(AContext.Tree.Root);
end;

{ TLoadWithoutEncodingRule }

const
  cTextFileMethods: array[0..3] of string = ('LoadFromFile', 'SaveToFile', 'LoadFromStream', 'SaveToStream');
  // Typen, deren LoadFromFile/SaveToFile Text mit TEncoding lesen bzw. schreiben.
  cStringListTypes: array[0..5] of string = ('TStrings', 'TStringList', 'THashedStringList', 'TMemoStrings',
    'TRichEditStrings', 'TAnsiStringList');
  // Properties der VCL- und FireDAC-Komponenten vom Typ TStrings.
  cStringListProperties: array[0..3] of string = ('Lines', 'Items', 'SQL', 'Strings');
  // TFile-Methoden, die ohne BOM TEncoding.Default lesen; WriteAllText und TStreamReader nehmen UTF-8.
  cReadAllMethods: array[0..1] of string = ('ReadAllText', 'ReadAllLines');

function TLoadWithoutEncodingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLoadWithoutEncodingRuleId, TRuleSeverity.Warning,
    cTexts[TPlatformText.EncodingTitle].Text);
end;

procedure TLoadWithoutEncodingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTypes: TDeclaredTypes;
  mTokens: TTokens;
  mEncoding: string;

  // Empfänger von LoadFromFile ist sicher eine Stringliste.
  function IsStringList(AReceiver: TSyntaxNode): Boolean;
  var
    mTypeName: string;
  begin
    case AReceiver.Kind of
      TSyntaxKind.Identifier:
        begin
          mTypeName := mTypes.DeclaredType(AReceiver.Name, AReceiver.StartPos);
          Result := MatchText(mTypeName, cStringListTypes);
        end;
      TSyntaxKind.MemberAccess:
        Result := MatchText(AReceiver.Name, cStringListProperties);
    else
      Result := False;
    end;
  end;

  function RoutineOf(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      Result := Result.Parent;
    end;
  end;

  // X.DefaultEncoding := …
  function IsDefaultEncodingAssign(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and SameText(ANode[0].Name, 'DefaultEncoding') and
      (ANode[0].ChildCount = 1);
  end;

  // X.LoadFrom…(Datei, Kodierung)
  function IsLoadWithEncoding(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 3) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and StartsText('LoadFrom', ANode[0].Name) and
      (ANode[0].ChildCount = 1);
  end;

  // LoadFromFile(Datei, Kodierung) vor ACall in derselben Routine merkt sich die Kodierung für SaveToFile.
  function LoadedWithEncoding(ACall: TSyntaxNode; const AReceiver: string): Boolean;
  var
    mNode, mRoutine: TSyntaxNode;
  begin
    Result := False;
    mRoutine := RoutineOf(ACall);
    if mRoutine = nil then
    begin
      Exit;
    end;
    for mNode in NodesOf(mRoutine, True) do
    begin
      if IsLoadWithEncoding(mNode) and (mNode.StartOffset < ACall.StartOffset) and
        SameText(NodeText(AContext, mNode[0][0]), AReceiver) then
      begin
        Exit(True);
      end;
    end;
  end;

  // Empfänger.DefaultEncoding := … in der Datei oder Laden mit Kodierung vor ACall in derselben Routine.
  function EncodingKnown(ACall: TSyntaxNode; const AReceiver: string): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    for mNode in NodesOf(AContext.Tree.Root, False) do
    begin
      if IsDefaultEncodingAssign(mNode) and SameText(NodeText(AContext, mNode[0][0]), AReceiver) then
      begin
        Exit(True);
      end;
    end;
    Result := LoadedWithEncoding(ACall, AReceiver);
  end;

  function Fix(ACall: TSyntaxNode): TArray<TRuleFix>;
  var
    mLast: TSyntaxNode;
    mEdits: TArray<TRuleEdit>;
    mExtra: TTextEdit;
  begin
    mLast := ACall[ACall.ChildCount - 1];
    mEdits := [TRuleEdit.Create(TTextRange.Create(mLast.EndPos, mLast.EndPos), ', TEncoding.' + mEncoding)];
    if UsesEdit(AContext, mTokens, ACall.StartOffset, 'System.SysUtils', mExtra) then
    begin
      mEdits := mEdits + [mExtra];
    end;
    Result := [TRuleFix.Create(cTexts[TPlatformText.AddEncoding].Fmt([mEncoding]), mEdits)];
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    mCallee: TSyntaxNode;
    mMethod, mReceiver: string;
  begin
    mCallee := ACall[0];
    if (mCallee.Kind <> TSyntaxKind.MemberAccess) or (mCallee.ChildCount <> 1) or (ACall.ChildCount <> 2) then
    begin
      Exit;
    end;
    mMethod := mCallee.Name;
    if MatchText(mMethod, cReadAllMethods) and IsQualifiedName(mCallee[0]) and IsName(mCallee[0], 'TFile') then
    begin
      AReport.Add(NodeRange(mCallee), cTexts[TPlatformText.FileNoEncoding].Fmt([mMethod]), TRuleConfidence.Medium,
        Fix(ACall));
      Exit;
    end;
    if not MatchText(mMethod, cTextFileMethods) or not IsStringList(mCallee[0]) then
    begin
      Exit;
    end;
    mReceiver := NodeText(AContext, mCallee[0]);
    if StartsText('Load', mMethod) then
    begin
      if not EncodingKnown(ACall, mReceiver) then
      begin
        AReport.Add(NodeRange(mCallee), cTexts[TPlatformText.ReadNoEncoding].Fmt(
          [mMethod]), TRuleConfidence.Medium, Fix(ACall));
      end;
    end
    else if not EncodingKnown(ACall, mReceiver) then
    begin
      AReport.Add(NodeRange(mCallee), cTexts[TPlatformText.WriteNoEncoding].Fmt([mMethod]), TRuleConfidence.Medium,
        Fix(ACall));
    end;
  end;

var
  mNode: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mEncoding := TRuleOptions.Text(AContext.Options, 'defaultEncoding', cDefaultEncoding);
  if IndexText(mEncoding, cEncodings) < 0 then
  begin
    mEncoding := cDefaultEncoding;
  end
  else
  begin
    mEncoding := cEncodings[IndexText(mEncoding, cEncodings)];
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mNode in NodesOf(AContext.Tree.Root, False) do
    begin
      if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) then
      begin
        CheckCall(mNode);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TRegistryHklmWriteRule }

const
  // Methoden von TRegistry, die schreiben; OpenKey nur mit CanCreate = True.
  cRegistryWrites: array[0..16] of string = ('CreateKey', 'DeleteKey', 'DeleteValue', 'RenameValue', 'MoveKey',
    'WriteString', 'WriteExpandString', 'WriteInteger', 'WriteBool', 'WriteFloat', 'WriteCurrency', 'WriteDate',
    'WriteTime', 'WriteDateTime', 'WriteBinaryData', 'SaveKey', 'RestoreKey');

function TRegistryHklmWriteRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cRegistryHklmWriteRuleId, TRuleSeverity.Hint, cTexts[TPlatformText.HklmTitle].Text);
end;

procedure TRegistryHklmWriteRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mPaths: TArray<string>;

  function IsRootKeyAssign(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and SameText(ANode[0].Name, 'RootKey') and
      (ANode[0].ChildCount = 1);
  end;

  // Reg.WriteString(…), Reg.OpenKey(…, True): Empfänger als Text, sonst ''.
  function WriteReceiver(ANode: TSyntaxNode): string;
  var
    mCallee: TSyntaxNode;
  begin
    Result := '';
    if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount = 0) then
    begin
      Exit;
    end;
    mCallee := ANode[0];
    if (mCallee.Kind <> TSyntaxKind.MemberAccess) or (mCallee.ChildCount <> 1) then
    begin
      Exit;
    end;
    if MatchText(mCallee.Name, cRegistryWrites) or (SameText(mCallee.Name, 'OpenKey') and (ANode.ChildCount = 3) and
      IsName(ANode[2], 'True')) then
    begin
      Result := NodeText(AContext, mCallee[0]);
    end;
  end;

  // Schreibt ein späteres Ereignis über AReceiver, bevor ein neuer RootKey sicher gilt?
  function WrittenLater(const AEvents: TArray<TSyntaxNode>; AIndex: Integer; const AReceiver: string): Boolean;
  var
    mLater: Integer;
    mAssign, mEvent: TSyntaxNode;
  begin
    Result := False;
    mAssign := AEvents[AIndex];
    for mLater := AIndex + 1 to High(AEvents) do
    begin
      mEvent := AEvents[mLater];
      // Ein neuer RootKey, der immer mit dieser Zuweisung übersetzt wird, gilt für alles danach.
      if IsRootKeyAssign(mEvent) then
      begin
        if SameText(NodeText(AContext, mEvent[0][0]), AReceiver) and
          TConditionalBranches.Implies(PathOf(mPaths, mTokens, mEvent), PathOf(mPaths, mTokens, mAssign)) then
        begin
          Exit;
        end;
      end
      else if SameText(WriteReceiver(mEvent), AReceiver) and
        not TConditionalBranches.Exclusive(PathOf(mPaths, mTokens, mEvent), PathOf(mPaths, mTokens, mAssign)) then
      begin
        Exit(True);
      end;
    end;
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    mEvents: TArray<TSyntaxNode>;
    mIndex: Integer;
    mAssign, mEvent: TSyntaxNode;
  begin
    // Zuweisungen an RootKey und schreibende Aufrufe in Reihenfolge des Quelltexts.
    mEvents := nil;
    // Lokale Routinen prüft CheckRoutine für sich.
    for mEvent in NodesOf(ARoutine, True) do
    begin
      if IsRootKeyAssign(mEvent) or (WriteReceiver(mEvent) <> '') then
      begin
        mEvents := mEvents + [mEvent];
      end;
    end;
    for mIndex := 0 to High(mEvents) do
    begin
      mAssign := mEvents[mIndex];
      if not IsRootKeyAssign(mAssign) or not IsName(mAssign[1], 'HKEY_LOCAL_MACHINE') then
      begin
        Continue;
      end;
      if WrittenLater(mEvents, mIndex, NodeText(AContext, mAssign[0][0])) then
      begin
        AReport.Add(NodeRange(mAssign[1]), cTexts[TPlatformText.Hklm].Text, TRuleConfidence.High,
          [TRuleFix.Create(cTexts[TPlatformText.UseHkcu].Text, [TRuleEdit.Create(NodeRange(mAssign[1]),
          'HKEY_CURRENT_USER')])]);
      end;
    end;
  end;

var
  mRoutine: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mPaths := TConditionalBranches.Paths(mTokens);
  for mRoutine in TRuleDerived.Routines(TRuleDerived.Open(AContext), AContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

{ TNowForElapsedTimeRule }

const
  // DateUtils-Funktionen, die den Abstand zweier Zeitpunkte liefern.
  cBetweenFunctions: array[0..9] of string = ('MilliSecondsBetween', 'SecondsBetween', 'MinutesBetween',
    'HoursBetween', 'MilliSecondSpan', 'SecondSpan', 'MinuteSpan', 'HourSpan', 'DaysBetween', 'DaySpan');
  // Die Korrektur ersetzt nur diese, mit dem passenden Teiler für ElapsedMilliseconds.
  cStopwatchFunctions: array[0..2] of string = ('MilliSecondsBetween', 'SecondsBetween', 'MinutesBetween');
  cStopwatchDivisors: array[0..2] of string = ('', ' div 1000', ' div 60000');

type
  /// <summary>Zuweisung "Start := Now" bzw. "var Start := Now" in einer Routine.</summary>
  TNowStart = record
    Name: string;
    Node: TSyntaxNode;
  end;

  /// <summary>Lauf der Regel über die Routinen einer Unit; FStarts gilt für die gerade geprüfte Routine.</summary>
  TNowElapsedScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TTokens;
    FPaths: TArray<string>;
    FRoutine: TSyntaxNode;
    FStarts: TArray<TNowStart>;
    procedure CollectStarts;
    function StartOf(ANode, AAt: TSyntaxNode): Integer;
    function MeasuredStart(ANode: TSyntaxNode): Integer;
    function IsUniqueStart(AStart: Integer): Boolean;
    function StartDecl(AStart: Integer; out ATypeNode: TSyntaxNode): Boolean;
    function IsStopwatchMeasure(ANode: TSyntaxNode; const AName: string): Boolean;
    function CollectMeasured(AStart: Integer; out AMeasured: TArray<TSyntaxNode>): Boolean;
    function FreeName(const AName: string): string;
    function RenameEdits(const AName, ANewName: string; const AMeasured: TArray<TSyntaxNode>): TArray<TRuleEdit>;
    function Fixes(AStart: Integer): TArray<TRuleFix>;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  end;

// Now, Now() oder SysUtils.Now
function IsNow(ANode: TSyntaxNode): Boolean;
begin
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 1) then
  begin
    ANode := ANode[0];
  end;
  Result := IsName(ANode, 'Now') and IsQualifiedName(ANode);
end;

// MilliSecondsBetween(Now, …) und Verwandte, die TStopwatch ersetzen kann.
function IsStopwatchCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 3) and IsQualifiedName(ANode[0]) and
    (IndexText(ANode[0].Name, cStopwatchFunctions) >= 0) and IsNow(ANode[1]);
end;

function InsideAny(AOffset: Integer; const ANodes: TArray<TSyntaxNode>): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in ANodes do
  begin
    if (AOffset >= mNode.StartOffset) and (AOffset < mNode.EndOffset) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TNowElapsedScan }

constructor TNowElapsedScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
end;

procedure TNowElapsedScan.CollectStarts;
var
  mNode: TSyntaxNode;
  mItem: TNowStart;
begin
  FStarts := nil;
  for mNode in NodesOf(FRoutine, True) do
  begin
    mItem.Node := mNode;
    if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount = 2) and
      (mNode[0].Kind = TSyntaxKind.Identifier) and IsNow(mNode[1]) then
    begin
      mItem.Name := mNode[0].Name;
      FStarts := FStarts + [mItem];
    end
    else if (mNode.Kind = TSyntaxKind.InlineVar) and (Pos(',', mNode.Name) = 0) and (mNode.ChildCount > 0) and
      IsNow(mNode[mNode.ChildCount - 1]) then
    begin
      mItem.Name := mNode.Name;
      FStarts := FStarts + [mItem];
    end;
  end;
end;

procedure TNowElapsedScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mMeasures: TArray<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  FRoutine := ARoutine;
  CollectStarts;
  if FStarts = nil then
  begin
    Exit;
  end;
  // Teilausdrücke einer Messung nicht noch einmal melden.
  mMeasures := nil;
  for mNode in NodesOf(ARoutine, True) do
  begin
    if not InsideAny(mNode.StartOffset, mMeasures) and (MeasuredStart(mNode) >= 0) then
    begin
      mMeasures := mMeasures + [mNode];
    end;
  end;
  for mNode in mMeasures do
  begin
    FReport.Add(NodeRange(mNode), cTexts[TPlatformText.NowMeasure].Text, TRuleConfidence.High,
      Fixes(MeasuredStart(mNode)));
  end;
end;

// Variable AName, der vor AAt in einem nicht ausschließenden Zweig Now zugewiesen wurde: Index, sonst -1.
function TNowElapsedScan.StartOf(ANode, AAt: TSyntaxNode): Integer;
var
  mItem: Integer;
begin
  Result := -1;
  if ANode.Kind <> TSyntaxKind.Identifier then
  begin
    Exit;
  end;
  for mItem := 0 to High(FStarts) do
  begin
    if SameText(FStarts[mItem].Name, ANode.Name) and (FStarts[mItem].Node.StartOffset < AAt.StartOffset) and
      not TConditionalBranches.Exclusive(PathOf(FPaths, FTokens, FStarts[mItem].Node),
        PathOf(FPaths, FTokens, AAt)) then
    begin
      Result := mItem;
    end;
  end;
end;

// Now - Start, Ende - Start, MilliSecondsBetween(Now, Start): Index des Starts, sonst -1.
function TNowElapsedScan.MeasuredStart(ANode: TSyntaxNode): Integer;
var
  mA, mB: TSyntaxNode;
begin
  Result := -1;
  if (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '-') and (ANode.ChildCount = 2) then
  begin
    mA := ANode[0];
    mB := ANode[1];
  end
  else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 3) and IsQualifiedName(ANode[0]) and
    MatchText(ANode[0].Name, cBetweenFunctions) then
  begin
    mA := ANode[1];
    mB := ANode[2];
  end
  else
  begin
    Exit;
  end;
  if IsNow(mA) or (StartOf(mA, ANode) >= 0) then
  begin
    Result := StartOf(mB, ANode);
  end;
  if (Result < 0) and (IsNow(mB) or (StartOf(mB, ANode) >= 0)) then
  begin
    Result := StartOf(mA, ANode);
  end;
end;

// Nur eine Zuweisung von Now an die Variable.
function TNowElapsedScan.IsUniqueStart(AStart: Integer): Boolean;
var
  mItem: Integer;
begin
  for mItem := 0 to High(FStarts) do
  begin
    if (mItem <> AStart) and SameText(FStarts[mItem].Name, FStarts[AStart].Name) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

// Lokale TDateTime-Variable (var-Abschnitt mit Typ oder die Inline-Variable des Starts selbst).
function TNowElapsedScan.StartDecl(AStart: Integer; out ATypeNode: TSyntaxNode): Boolean;
var
  mDecl, mNode: TSyntaxNode;
begin
  ATypeNode := nil;
  mDecl := nil;
  for mNode in NodesOf(FRoutine, True) do
  begin
    if (mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar]) and SameText(mNode.Name, FStarts[AStart].Name) then
    begin
      mDecl := mNode;
    end;
  end;
  if mDecl = nil then
  begin
    Exit(False);
  end;
  ATypeNode := mDecl.FindChild(TSyntaxKind.TypeReference);
  if ATypeNode <> nil then
  begin
    Result := SameText(ATypeNode.Name, 'TDateTime');
  end
  else
  begin
    Result := mDecl.Kind = TSyntaxKind.InlineVar;
  end;
  if Result and (mDecl.Kind = TSyntaxKind.InlineVar) then
  begin
    Result := mDecl = FStarts[AStart].Node;
  end;
end;

// MilliSecondsBetween(Now, AName) und Verwandte.
function TNowElapsedScan.IsStopwatchMeasure(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := IsStopwatchCall(ANode) and (ANode[2].Kind = TSyntaxKind.Identifier) and SameText(ANode[2].Name, AName);
end;

// Jede andere Erwähnung muss eine Messung sein, die sich umschreiben lässt.
function TNowElapsedScan.CollectMeasured(AStart: Integer; out AMeasured: TArray<TSyntaxNode>): Boolean;
var
  mNode, mStartNode: TSyntaxNode;
  mName: string;
begin
  AMeasured := nil;
  mName := FStarts[AStart].Name;
  mStartNode := FStarts[AStart].Node;
  for mNode in NodesOf(FRoutine, True) do
  begin
    if InsideAny(mNode.StartOffset, AMeasured) then
    begin
      Continue;
    end;
    if IsStopwatchMeasure(mNode, mName) then
    begin
      AMeasured := AMeasured + [mNode];
    end
    else if (mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, mName) and
      not ((mNode.Parent = mStartNode) and (mNode.Parent[0] = mNode)) then
    begin
      Exit(False);
    end;
  end;
  Result := AMeasured <> nil;
end;

// Wie im Issue heißt Start danach Uhr, wenn der Name in der Datei frei ist.
function TNowElapsedScan.FreeName(const AName: string): string;
var
  mItem: Integer;
begin
  Result := 'Uhr';
  for mItem := 0 to High(FTokens) do
  begin
    if (FTokens[mItem].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[mItem].Text, 'Uhr') then
    begin
      Exit(AName);
    end;
  end;
end;

function TNowElapsedScan.RenameEdits(const AName, ANewName: string;
  const AMeasured: TArray<TSyntaxNode>): TArray<TRuleEdit>;
var
  mItem: Integer;
begin
  Result := nil;
  for mItem := TokenFrom(FTokens, FRoutine.StartOffset) to High(FTokens) do
  begin
    if FTokens[mItem].Offset >= FRoutine.EndOffset then
    begin
      Break;
    end;
    if (FTokens[mItem].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[mItem].Text, AName) and
      not InsideAny(FTokens[mItem].Offset, AMeasured) then
    begin
      Result := Result + [TRuleEdit.Create(TTextRange.Create(FTokens[mItem].StartPos, FTokens[mItem].EndPos),
        ANewName)];
    end;
  end;
end;

// Korrektur nur, wenn Start eine lokale TDateTime-Variable allein für Messungen wie
// MilliSecondsBetween(Now, Start) ist.
function TNowElapsedScan.Fixes(AStart: Integer): TArray<TRuleFix>;
var
  mTypeNode, mUse, mValue: TSyntaxNode;
  mMeasured: TArray<TSyntaxNode>;
  mEdits: TArray<TRuleEdit>;
  mExtra: TTextEdit;
  mName, mNewName: string;
begin
  Result := nil;
  if not IsUniqueStart(AStart) or not StartDecl(AStart, mTypeNode) or not CollectMeasured(AStart, mMeasured) then
  begin
    Exit;
  end;
  mName := FStarts[AStart].Name;
  mNewName := FreeName(mName);
  mEdits := nil;
  if mTypeNode <> nil then
  begin
    mEdits := mEdits + [TRuleEdit.Create(NodeRange(mTypeNode), 'TStopwatch')];
  end;
  mValue := FStarts[AStart].Node[FStarts[AStart].Node.ChildCount - 1];
  mEdits := mEdits + [TRuleEdit.Create(NodeRange(mValue), 'TStopwatch.StartNew')];
  for mUse in mMeasured do
  begin
    mEdits := mEdits + [TRuleEdit.Create(NodeRange(mUse), mNewName + '.ElapsedMilliseconds' +
      cStopwatchDivisors[IndexText(mUse[0].Name, cStopwatchFunctions)])];
  end;
  if not SameText(mNewName, mName) then
  begin
    mEdits := mEdits + RenameEdits(mName, mNewName, mMeasured);
  end;
  if UsesEdit(FContext, FTokens, FRoutine.StartOffset, 'System.Diagnostics', mExtra) then
  begin
    mEdits := mEdits + [mExtra];
  end;
  Result := [TRuleFix.Create(cTexts[TPlatformText.ToStopwatch].Text, mEdits)];
end;

{ TNowForElapsedTimeRule }

function TNowForElapsedTimeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cNowForElapsedTimeRuleId, TRuleSeverity.Hint, cTexts[TPlatformText.NowTitle].Text);
end;

procedure TNowForElapsedTimeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TNowElapsedScan;
  mRoutine: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mScan := TNowElapsedScan.Create(AContext, AReport);
  try
    for mRoutine in TRuleDerived.Routines(TRuleDerived.Open(AContext), AContext) do
    begin
      mScan.CheckRoutine(mRoutine);
    end;
  finally
    mScan.Free;
  end;
end;

procedure RegisterPlatformRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUiCallInConsoleOrServiceRule.Create);
  ARegistry.Register(TLoadWithoutEncodingRule.Create);
  ARegistry.Register(TRegistryHklmWriteRule.Create);
  ARegistry.Register(TNowForElapsedTimeRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Platform', cTexts);

end.
