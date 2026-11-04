unit Atlas.Common.Rules.Builtin.Flow;

// Flussregeln (#269) auf dem Kontrollflussgraphen (#143):
//   result-not-set            Funktion kann enden, ohne Result zu setzen (wie W1035)
//   possibly-uninitialized    lokale Variable wird möglicherweise vor der ersten
//                             Zuweisung gelesen (wie W1036)
//   unreachable-code          Anweisung nach Exit, raise, Abort, goto … wird nie
//                             ausgeführt (#94); gemeldet wird nur die erste
//                             Anweisung eines unerreichbaren Abschnitts
//   use-after-free            nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X)
//                             oder Dispose(X) wird X ohne neue Zuweisung wieder
//                             benutzt (#915): X.Methode, X.Feld, X[…], X^, with X,
//                             nach Free auch Assigned(X) und ein zweites Free.
//                             Vom Freigabeknoten aus folgt die Regel dem Graphen;
//                             eine Zuweisung an X, die Übergabe von X an eine
//                             Routine, @X und nach FreeAndNil eine Abfrage auf nil
//                             (Assigned(X), X <> nil) beenden den Weg. Konfidenz
//                             hoch, wenn Freigabe und Zugriff im selben Block
//                             nacheinander stehen, sonst mittel. Die Aktion
//                             springt zur Freigabe.
//   deref-before-nil-check    X wird benutzt (X.Feld, X.Methode, X[…], X^) und
//                             erst danach mit Assigned(X), X <> nil oder X = nil
//                             geprüft (#916). Still, wenn vor dem Zugriff schon
//                             geprüft wurde, wenn X dazwischen neu gesetzt oder
//                             übergeben wird und bei Feldern und globalen
//                             Variablen nach jedem Aufruf dazwischen (er kann
//                             sie ändern). Steht die Prüfung als if ohne else
//                             direkt nach dem Zugriff im selben Block, zieht die
//                             Korrektur sie vor den Zugriff.
//   field-free-without-nil    FFeld.Free in einer Methode außerhalb des
//                             Destruktors, und ein Weg zum Ende der Methode
//                             setzt das Feld nicht neu (#917). Neu setzt eine
//                             Zuweisung oder der Aufruf einer Methode derselben
//                             Klasse, die das Feld zuweist. Felder sind die der
//                             Klassendeklaration in der Unit. Ausgenommen sind
//                             die Methoden aus ignoreMethods (Vorgabe Destroy,
//                             BeforeDestruction); Korrektur FreeAndNil(FFeld).
//   destructor-not-nil-safe   Der Destruktor (oder eine Methode, die nur er
//                             aufruft) benutzt ein Feld (FFeld.Clear), das ein
//                             Konstruktor erst nach Code anlegt, der eine
//                             Exception werfen kann, oder nur bedingt (#1087).
//                             Wirft der Konstruktor, ruft Delphi den Destruktor
//                             mit dem noch leeren Feld auf. Free, FreeAndNil,
//                             DisposeOf und Zugriffe nach Assigned(FFeld) bzw.
//                             FFeld <> nil sind sicher; BeforeDestruction läuft
//                             auf diesem Weg nicht. Mit onlyAfterRaisingCode
//                             aus zählt jedes im Konstruktor angelegte Feld.
//                             Korrektur: if Assigned(FFeld) then davor.
//   handle-leak               Ein Windows-Handle aus CreateFile, CreateEvent,
//                             OpenProcess, CreateProcess (hProcess, hThread),
//                             FindFirstFile, RegOpenKeyEx, LoadLibrary, GetDC,
//                             GDI-Objekten … in einer lokalen Variablen wird
//                             auf einem Weg zum Ende der Routine nicht mit dem
//                             passenden Gegenstück geschlossen (#1088). Die
//                             Paare stehen in BuiltinHandlePairs, eigene über
//                             die Option pairs. Zurückgeben, Speichern und
//                             Übergabe an unbekannte Routinen gelten als
//                             Weitergabe, ebenso [H] in einem Array-Ausdruck;
//                             Zweige, in denen das Öffnen laut if-Prüfung
//                             misslang, und Ausnahmewege
//                             (pair-without-finally) zählen nicht. Korrektur:
//                             die Anweisungen danach in try … finally mit dem
//                             Schließen einschließen.
//   out-param-read            out-Parameter wird gelesen, bevor die Routine ihn
//                             setzt (#924); bei verwalteten Typen hat ihn der
//                             Aufrufer schon geleert. Korrektur out -> var in
//                             Implementierung und Deklaration.
//   noreturn-returns          Eine noreturn-Routine (ab Delphi 13) kann normal
//                             zurückkehren (#1132): Ein Weg erreicht das Ende des
//                             Rumpfs oder ein Exit, ohne über raise, Abort, Halt,
//                             RunError oder den Aufruf einer anderen noreturn-
//                             Routine zu gehen. Die Direktive zählt an der
//                             Implementierung und an der Deklaration (interface,
//                             Klasse). Aufrufe, deren Ziel weder die Datei, die
//                             Standardroutinen noch der Symbolindex kennt, könnten
//                             selbst noreturn sein und beenden den Weg ebenfalls;
//                             gemeldet wird also nur ein Weg ganz aus bekannten
//                             Anweisungen. Exit wird an der Anweisung gemeldet,
//                             das Ende des Rumpfs am Routinennamen.
//
// Was der Graph nicht sieht, macht die Variable "unbekannt" und erzeugt keinen
// Treffer: Übergabe als Argument (var/out-Parameter, SetLength, FillChar,
// TryGetValue …), @X, Zuweisung an ein Feld oder Element (Result.Feld := …,
// Result[I] := …), with X do, inherited in Funktionen und die alte Zuweisung
// an den Funktionsnamen. Ist der Graph unvollständig (asm, Syntaxfehler),
// gibt es ebenfalls keinen Treffer.
//
// possibly-uninitialized prüft nur Variablen, die Delphi nicht selbst
// vorbelegt: einfache Typen (Konfidenz hoch) und T…-Typen wie Klassen und
// Records (Konfidenz mittel). string, Variant, Interfaces und dynamische
// Arrays sind verwaltet und werden übergangen.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Flow.Uninitialized,
  Atlas.Common.Rules.Builtin.Flow.UseAfterFree,
  Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck,
  Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil,
  Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe;

type
  TResultNotSetRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.Uninitialized.</summary>
  TPossiblyUninitializedRule = Atlas.Common.Rules.Builtin.Flow.Uninitialized.TPossiblyUninitializedRule;

  TUnreachableCodeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.UseAfterFree.</summary>
  TUseAfterFreeRule = Atlas.Common.Rules.Builtin.Flow.UseAfterFree.TUseAfterFreeRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck.</summary>
  TDerefBeforeNilCheckRule = Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck.TDerefBeforeNilCheckRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil.</summary>
  TFieldFreeWithoutNilRule = Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil.TFieldFreeWithoutNilRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.</summary>
  TDestructorNotNilSafeRule = Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.TDestructorNotNilSafeRule;

  THandleLeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Paare "Öffnen|Ort|Schließen" aus der Tabelle und der Option pairs ("Öffnen&gt;Schließen" oder
    /// {"open", "close"}).</summary>
    class function Pairs(const AOptions: string): TArray<string>; static;
  end;

  TOutParamReadRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TNoreturnReturnsRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  OutParamReadRuleId = 'out-param-read';
  UseAfterFreeRuleId = Atlas.Common.Rules.Builtin.Flow.UseAfterFree.UseAfterFreeRuleId;
  DerefBeforeNilCheckRuleId = Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck.DerefBeforeNilCheckRuleId;
  FieldFreeWithoutNilRuleId = Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil.FieldFreeWithoutNilRuleId;
  DestructorNotNilSafeRuleId = Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.DestructorNotNilSafeRuleId;
  HandleLeakRuleId = 'handle-leak';
  NoreturnReturnsRuleId = 'noreturn-returns';

/// <summary>Wird AName in ABlock so benutzt, dass der Kontrollfluss die Zuweisung nicht sieht?</summary>
function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared;

function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;
begin
  Result := Atlas.Common.Rules.Builtin.Flow.Shared.HasOpaqueUse(ABlock, AName);
end;

{ TResultNotSetRule }

function TResultNotSetRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('result-not-set', TRuleSeverity.Warning,
    'Funktion kann enden, ohne Result zu setzen');
end;

procedure TResultNotSetRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Routine, Header, Block: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Name: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
    // Nur Funktionen: der Kopf trägt einen Ergebnistyp.
    if (Header = nil) or (Header.FindChild(TSyntaxKind.TypeReference) = nil) then
    begin
      Continue;
    end;
    Block := Routine.FindChild(TSyntaxKind.Block);
    Name := ShortName(Routine.Name);
    if HasOpaqueUse(Block, 'Result') or HasOpaqueUse(Block, Name) or ContainsKind(Block, TSyntaxKind.InheritedExpr) then
    begin
      Continue;
    end;
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    // Alte Schreibweise: Zuweisung an den Funktionsnamen setzt ebenfalls das Ergebnis.
    if (Graph.MayEndWithout('Result') = TFlowAnswer.Yes) and (Graph.MayEndWithout(Name) = TFlowAnswer.Yes) then
    begin
      AReport.Add(HeaderNameRange(AContext, Routine),
        Format('"%s" kann enden, ohne Result zu setzen; der Rückgabewert ist dann undefiniert', [Name]),
        TRuleConfidence.High);
    end;
  end;
end;

{ TUnreachableCodeRule }

function TUnreachableCodeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unreachable-code', TRuleSeverity.Warning, 'Anweisung wird nie ausgeführt');
end;

/// <summary>Bereich der ersten Zeile von ANode; mehrzeilige Anweisungen werden nicht ganz markiert.</summary>
function FirstLineRange(const AContext: TRuleContext; ANode: TSyntaxNode): TTextRange;
var
  Token: TPascalToken;
  mIndex: Integer;
  Last: TTextPosition;
begin
  Last := ANode.EndPos;
  if Last.Line <> ANode.StartPos.Line then
  begin
    Last := ANode.StartPos;
    for mIndex := AContext.Tree.FirstTokenFrom(ANode.StartOffset) to High(AContext.Tree.Tokens) do
    begin
      Token := AContext.Tree.Tokens[mIndex];
      if Token.Offset >= ANode.EndOffset then
      begin
        Break;
      end;
      if (Token.Offset >= ANode.StartOffset) and (Token.StartPos.Line = ANode.StartPos.Line) and
        (Token.Kind <> TPascalTokenKind.Comment) then
      begin
        Last := Token.EndPos;
      end;
    end;
  end;
  Result := TTextRange.Create(ANode.StartPos, Last);
end;

procedure TUnreachableCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Dead: TArray<TSyntaxNode>;
  Routine: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Unreachable: TArray<TFlowNode>;
  Node: TFlowNode;

  function IsDead(ANode: TSyntaxNode): Boolean;
  var
    Item: TSyntaxNode;
  begin
    for Item in Dead do
    begin
      if Item = ANode then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Liegt eine unerreichbare Anweisung in ANode (oder ist es ANode selbst)? Iterativ (Bericht M1): von den
  // unerreichbaren Anweisungen aufwärts statt rekursiv durch ANode.
  function HasDead(ANode: TSyntaxNode): Boolean;
  var
    Item, Current: TSyntaxNode;
  begin
    for Item in Dead do
    begin
      Current := Item;
      while Current <> nil do
      begin
        if Current = ANode then
        begin
          Exit(True);
        end;
        Current := Current.Parent;
      end;
    end;
    Result := False;
  end;

  // Erste Anweisung eines unerreichbaren Abschnitts: nicht in einer anderen
  // unerreichbaren Anweisung enthalten, und davor steht (auf der ersten Ebene,
  // die einen Vorgänger hat) erreichbarer Code.
  function StartsDeadRun(AStatement: TSyntaxNode): Boolean;
  var
    Current, Parent: TSyntaxNode;
    Index: Integer;
  begin
    Current := AStatement.Parent;
    while (Current <> nil) and (Current <> Routine) do
    begin
      if IsDead(Current) then
      begin
        Exit(False);
      end;
      Current := Current.Parent;
    end;
    Current := AStatement;
    while (Current <> Routine) and (Current.Parent <> nil) do
    begin
      Parent := Current.Parent;
      for Index := 1 to Parent.ChildCount - 1 do
      begin
        if Parent[Index] = Current then
        begin
          Exit(not HasDead(Parent[Index - 1]));
        end;
      end;
      Current := Parent;
    end;
    Result := True;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
    begin
      Continue;
    end;
    Unreachable := Graph.UnreachableStatements;
    Dead := nil;
    for Node in Unreachable do
    begin
      if Node.Syntax <> nil then
      begin
        Dead := Dead + [Node.Syntax];
      end;
    end;
    for Node in Unreachable do
    begin
      if (Node.Syntax <> nil) and StartsDeadRun(Node.Syntax) then
      begin
        AReport.Add(FirstLineRange(AContext, Node.Syntax), 'Diese Anweisung wird nie ausgeführt',
          TRuleConfidence.High);
      end;
    end;
  end;
end;

{ THandleLeakRule }

const
  /// <summary>Öffnen|Ort|Schließen: Ort r = Ergebnis, Zahlen = out-Argumente (ab 0), Zahl:Feld,Feld = Felder
  /// eines Record-Arguments (CreateProcess). Im Schließen steht %h für das Handle, %0 für das erste Argument
  /// des Öffnens. Namen mit A/W am Ende gelten mit.</summary>
  BuiltinHandlePairs: array[0..64] of string = (
    'CreateFile|r|CloseHandle(%h)', 'CreateEvent|r|CloseHandle(%h)', 'CreateEventEx|r|CloseHandle(%h)',
    'CreateMutex|r|CloseHandle(%h)', 'CreateSemaphore|r|CloseHandle(%h)', 'CreateWaitableTimer|r|CloseHandle(%h)',
    'CreateThread|r|CloseHandle(%h)', 'CreateRemoteThread|r|CloseHandle(%h)', 'OpenProcess|r|CloseHandle(%h)',
    'OpenThread|r|CloseHandle(%h)', 'OpenEvent|r|CloseHandle(%h)', 'OpenMutex|r|CloseHandle(%h)',
    'OpenSemaphore|r|CloseHandle(%h)', 'CreateFileMapping|r|CloseHandle(%h)', 'OpenFileMapping|r|CloseHandle(%h)',
    'CreateNamedPipe|r|CloseHandle(%h)', 'CreateMailslot|r|CloseHandle(%h)',
    'CreateToolhelp32Snapshot|r|CloseHandle(%h)', 'CreateJobObject|r|CloseHandle(%h)',
    'OpenProcessToken|2|CloseHandle(%h)', 'OpenThreadToken|3|CloseHandle(%h)', 'DuplicateToken|2|CloseHandle(%h)',
    'CreatePipe|0,1|CloseHandle(%h)', 'CreateProcess|9:hProcess,hThread|CloseHandle(%h)',
    'CreateProcessAsUser|10:hProcess,hThread|CloseHandle(%h)', 'FindFirstFile|r|FindClose(%h)',
    'FindFirstFileEx|r|FindClose(%h)', 'FindFirstChangeNotification|r|FindCloseChangeNotification(%h)',
    'LoadLibrary|r|FreeLibrary(%h)', 'LoadLibraryEx|r|FreeLibrary(%h)', 'GetDC|r|ReleaseDC(%0, %h)',
    'GetWindowDC|r|ReleaseDC(%0, %h)', 'GetDCEx|r|ReleaseDC(%0, %h)', 'CreateCompatibleDC|r|DeleteDC(%h)',
    'CreateDC|r|DeleteDC(%h)', 'CreateIC|r|DeleteDC(%h)', 'CreatePen|r|DeleteObject(%h)',
    'CreatePenIndirect|r|DeleteObject(%h)', 'ExtCreatePen|r|DeleteObject(%h)', 'CreateFont|r|DeleteObject(%h)',
    'CreateFontIndirect|r|DeleteObject(%h)', 'CreateSolidBrush|r|DeleteObject(%h)',
    'CreateHatchBrush|r|DeleteObject(%h)', 'CreatePatternBrush|r|DeleteObject(%h)',
    'CreateBrushIndirect|r|DeleteObject(%h)', 'CreateBitmap|r|DeleteObject(%h)',
    'CreateCompatibleBitmap|r|DeleteObject(%h)', 'CreateDIBitmap|r|DeleteObject(%h)',
    'CreateDIBSection|r|DeleteObject(%h)', 'CreateRectRgn|r|DeleteObject(%h)',
    'CreateRectRgnIndirect|r|DeleteObject(%h)', 'CreateRoundRectRgn|r|DeleteObject(%h)',
    'CreateEllipticRgn|r|DeleteObject(%h)', 'CreatePolygonRgn|r|DeleteObject(%h)',
    'CreatePalette|r|DeleteObject(%h)', 'CreateIcon|r|DestroyIcon(%h)', 'CreateIconIndirect|r|DestroyIcon(%h)',
    'CopyIcon|r|DestroyIcon(%h)', 'ExtractIcon|r|DestroyIcon(%h)', 'OpenSCManager|r|CloseServiceHandle(%h)',
    'OpenService|r|CloseServiceHandle(%h)', 'CreateService|r|CloseServiceHandle(%h)',
    'RegOpenKeyEx|4|RegCloseKey(%h)', 'RegCreateKeyEx|7|RegCloseKey(%h)', 'MapViewOfFile|r|UnmapViewOfFile(%h)');
  /// <summary>Routinen, die ein Handle nur benutzen und es nicht übernehmen; jede andere Übergabe zählt als
  /// Weitergabe.</summary>
  HandleUsers: array[0..75] of string = ('WaitForSingleObject', 'WaitForSingleObjectEx', 'WaitForInputIdle',
    'MsgWaitForMultipleObjects', 'SignalObjectAndWait', 'ReadFile', 'WriteFile', 'ReadFileEx', 'WriteFileEx',
    'GetFileSize', 'GetFileSizeEx', 'SetFilePointer', 'SetFilePointerEx', 'SetEndOfFile', 'FlushFileBuffers',
    'GetFileTime', 'SetFileTime', 'GetFileType', 'GetFileInformationByHandle', 'LockFile', 'UnlockFile',
    'LockFileEx', 'UnlockFileEx', 'DeviceIoControl', 'GetOverlappedResult', 'SetEvent', 'ResetEvent', 'PulseEvent',
    'ReleaseMutex', 'ReleaseSemaphore', 'SetWaitableTimer', 'CancelWaitableTimer', 'TerminateProcess',
    'TerminateThread', 'GetExitCodeProcess', 'GetExitCodeThread', 'ResumeThread', 'SuspendThread',
    'SetThreadPriority', 'GetProcessTimes', 'GetProcessId', 'GetThreadId', 'QueryFullProcessImageName',
    'GetModuleFileNameEx', 'GetTokenInformation', 'AdjustTokenPrivileges', 'FindNextFile',
    'FindNextChangeNotification', 'Process32First', 'Process32Next', 'Module32First', 'Module32Next',
    'Thread32First', 'Thread32Next', 'PeekNamedPipe', 'ConnectNamedPipe', 'DisconnectNamedPipe', 'GetProcAddress',
    'RegQueryValueEx', 'RegSetValueEx', 'RegEnumKeyEx', 'RegEnumValue', 'RegDeleteValue', 'RegQueryInfoKey',
    'RegDeleteKey', 'SelectObject', 'GetObject', 'GetDeviceCaps', 'BitBlt', 'StretchBlt', 'TextOut', 'DrawText',
    'FillRect', 'FrameRect', 'FillRgn', 'PatBlt');

type
  /// <summary>Paar aus Tabelle oder Option.</summary>
  THandlePair = record
    Open: string;
    /// <summary>'r' für das Ergebnis, sonst Argumente wie '4', '0,1' oder '9:hProcess,hThread'.</summary>
    Where: string;
    Close: string;
  end;

  /// <summary>Ein geöffnetes Handle: Pfad (H, PI.hProcess) und Schließen.</summary>
  TOpenedHandle = record
    Path: string;
    /// <summary>Wurzel des Pfads (PI bei PI.hProcess); Weitergabe der Wurzel gibt auch das Handle weiter.</summary>
    Root: string;
    CloseName: string;
    CloseText: string;
  end;

function THandleLeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(HandleLeakRuleId, TRuleSeverity.Warning, 'Windows-Handle wird nicht geschlossen');
end;

class function THandleLeakRule.Pairs(const AOptions: string): TArray<string>;
var
  Value, List, Item: TJSONValue;
  Open, Close: string;
begin
  Result := nil;
  for Open in BuiltinHandlePairs do
  begin
    Result := Result + [Open];
  end;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    List := TJSONObject(Value).GetValue('pairs');
    if not (List is TJSONArray) then
    begin
      Exit;
    end;
    for Item in TJSONArray(List) do
    begin
      Open := '';
      Close := '';
      // "MeinOeffnen>MeinSchliessen" bzw. {"open": "MeinOeffnen", "close": "MeinSchliessen"}.
      if (Item is TJSONString) and (Pos('>', Item.Value) > 1) then
      begin
        Open := Trim(Copy(Item.Value, 1, Pos('>', Item.Value) - 1));
        Close := Trim(Copy(Item.Value, Pos('>', Item.Value) + 1, MaxInt));
      end
      else if Item is TJSONObject then
      begin
        if not TJSONObject(Item).TryGetValue<string>('open', Open) or
          not TJSONObject(Item).TryGetValue<string>('close', Close) then
        begin
          Continue;
        end;
        Open := Trim(Open);
        Close := Trim(Close);
      end;
      if (Open <> '') and (Close <> '') and IsValidIdent(Open, True) and IsValidIdent(Close, True) then
      begin
        Result := Result + [Open + '|r|' + Close + '(%h)'];
      end;
    end;
  finally
    Value.Free;
  end;
end;

procedure THandleLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Table: TArray<THandlePair>;
  Cache: IRuleDerivedCache;
  Graph: TControlFlowGraph;
  Locals: TArray<string>;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function Contains(const AList: TArray<string>; const AName: string): Boolean;
  var
    Item: string;
  begin
    for Item in AList do
    begin
      if SameText(Item, AName) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Name einer aufgerufenen Routine ohne Unit-Präfix (Winapi.Windows.CloseHandle).
  function CallName(ACall: TSyntaxNode): string;
  var
    Callee: TSyntaxNode;
  begin
    Result := '';
    if (ACall.Kind <> TSyntaxKind.Call) or (ACall.ChildCount = 0) then
    begin
      Exit;
    end;
    Callee := ACall[0];
    if Callee.Kind = TSyntaxKind.Identifier then
    begin
      Result := Callee.Name;
    end
    else if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount = 1) and
      MatchText(Trim(Text(Callee[0])), ['Windows', 'Winapi.Windows', 'ShellAPI', 'Winapi.ShellAPI', 'TlHelp32',
      'Winapi.TlHelp32', 'WinSvc', 'Winapi.WinSvc']) then
    begin
      Result := Callee.Name;
    end;
  end;

  // Gleicher Name, auch mit A/W-Endung (CreateFileW).
  function SameRoutine(const AName, ATableName: string): Boolean;
  begin
    Result := SameText(AName, ATableName) or ((Length(AName) = Length(ATableName) + 1) and
      StartsText(ATableName, AName) and CharInSet(AName[Length(AName)], ['A', 'W']));
  end;

  function PairOf(const AName: string; out APair: THandlePair): Boolean;
  var
    Pair: THandlePair;
  begin
    for Pair in Table do
    begin
      if SameRoutine(AName, Pair.Open) then
      begin
        APair := Pair;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Pfad eines Ausdrucks: H, PI.hProcess; sonst ''.
  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode.Kind = TSyntaxKind.Identifier then
    begin
      Result := ANode.Name;
    end
    else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) then
    begin
      Result := ANode[0].Name + '.' + ANode.Name;
    end;
  end;

  function CloseText(const APair: THandlePair; ACall: TSyntaxNode; const APath: string): string;
  begin
    Result := StringReplace(APair.Close, '%h', APath, [rfReplaceAll]);
    if (Pos('%0', Result) > 0) and (ACall.ChildCount > 1) then
    begin
      Result := StringReplace(Result, '%0', Trim(Text(ACall[1])), [rfReplaceAll]);
    end;
  end;

  // Handles, die ACall öffnet; ATarget ist das Ziel einer Zuweisung (nil ohne).
  function Opened(ACall: TSyntaxNode; const ATarget: string; out AHandles: TArray<TOpenedHandle>): Boolean;
  var
    Pair: THandlePair;
    Handle: TOpenedHandle;
    Part, Arg, Field: string;
    Parts, Fields: TArray<string>;
    Index: Integer;
  begin
    AHandles := nil;
    if not PairOf(CallName(ACall), Pair) then
    begin
      Exit(False);
    end;
    Handle.CloseName := Copy(Pair.Close, 1, Pos('(', Pair.Close) - 1);
    if Pair.Where = 'r' then
    begin
      if (ATarget <> '') and Contains(Locals, ATarget) then
      begin
        Handle.Path := ATarget;
        Handle.Root := ATarget;
        Handle.CloseText := CloseText(Pair, ACall, Handle.Path);
        AHandles := [Handle];
      end;
    end
    else
    begin
      Fields := nil;
      Part := Pair.Where;
      if Pos(':', Part) > 0 then
      begin
        Fields := Copy(Part, Pos(':', Part) + 1, MaxInt).Split([',']);
        Part := Copy(Part, 1, Pos(':', Part) - 1);
      end;
      Parts := Part.Split([',']);
      for Part in Parts do
      begin
        Index := StrToIntDef(Part, -1) + 1;
        if (Index < 1) or (Index >= ACall.ChildCount) then
        begin
          Continue;
        end;
        Arg := PathOf(ACall[Index]);
        if (Arg = '') or (Pos('.', Arg) > 0) or not Contains(Locals, Arg) then
        begin
          Continue;
        end;
        Handle.Root := Arg;
        if Fields = nil then
        begin
          Handle.Path := Arg;
          Handle.CloseText := CloseText(Pair, ACall, Handle.Path);
          AHandles := AHandles + [Handle];
        end
        else
        begin
          for Field in Fields do
          begin
            Handle.Path := Arg + '.' + Field;
            Handle.CloseText := CloseText(Pair, ACall, Handle.Path);
            AHandles := AHandles + [Handle];
          end;
        end;
      end;
    end;
    Result := AHandles <> nil;
  end;

  // Was ein Knoten selbst auswertet: einfache Anweisungen ganz, bei if, case und Schleifen die Bedingung bzw.
  // der Kopf, with ganz (with H do … gibt das Handle weiter).
  function Parts(ANode: TFlowNode): TArray<TSyntaxNode>;
  begin
    Result := nil;
    if ANode.Syntax = nil then
    begin
      Exit;
    end;
    if ANode.Syntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement,
      TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.WithStatement] then
    begin
      Result := [ANode.Syntax];
    end
    else if ANode.Kind = TFlowNodeKind.Condition then
    begin
      Result := OwnParts(ANode.Syntax);
    end;
  end;

  // Schließt E das Handle (CloseHandle(PI.hProcess), ReleaseDC(Wnd, DC))?
  function Closes(ARoot: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
  var
    Index: Integer;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
        begin
          Continue;
        end;
        if (E.Kind = TSyntaxKind.Call) and SameRoutine(CallName(E), AHandle.CloseName) then
        begin
          for Index := 1 to E.ChildCount - 1 do
          begin
            if SameText(PathOf(E[Index]), AHandle.Path) then
            begin
              Exit(True);
            end;
          end;
        end;
        for Index := E.ChildCount - 1 downto 0 do
        begin
          Pending.Push(E[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Kommt das Handle (oder seine Wurzel) in E vor?
  function Mentions(ARoot: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
  var
    Index: Integer;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if (E.Kind = TSyntaxKind.Identifier) and SameText(E.Name, AHandle.Root) and
          ((E.Parent = nil) or (E.Parent.Kind <> TSyntaxKind.MemberAccess) or (E.Parent[0] <> E) or
          SameText(PathOf(E.Parent), AHandle.Path) or (Pos('.', AHandle.Path) = 0)) then
        begin
          Exit(True);
        end;
        for Index := E.ChildCount - 1 downto 0 do
        begin
          Pending.Push(E[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Ist E das Handle selbst, seine Wurzel (PI) oder eine Typumwandlung davon (THandle(H), (H))?
  function IsHandleValue(E: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
  begin
    // Iterativ (Bericht M1): an Klammern und Typumwandlungen entlang nach innen.
    Result := False;
    while True do
    begin
      if SameText(PathOf(E), AHandle.Path) or ((E.Kind = TSyntaxKind.Identifier) and SameText(E.Name, AHandle.Root)) then
      begin
        Exit(True);
      end;
      if (E.Kind = TSyntaxKind.ParenExpr) and (E.ChildCount = 1) then
      begin
        E := E[0];
      end
      else if (E.Kind = TSyntaxKind.Call) and (E.ChildCount = 2) and (E[0].Kind = TSyntaxKind.Identifier) and
        MatchText(E[0].Name, ['THandle', 'HWND', 'HMODULE', 'HKEY', 'HDC', 'HGDIOBJ', 'Integer', 'Cardinal',
        'NativeInt', 'NativeUInt', 'Pointer', 'UIntPtr', 'IntPtr']) then
      begin
        E := E[1];
      end
      else
      begin
        Exit;
      end;
    end;
  end;

  // Gibt E das Handle weiter: Zuweisung an ein anderes Ziel, Exit(H), Übergabe an eine unbekannte Routine,
  // with, anonyme Methode?
  function PassesOn(ARoot: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Name: string;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if E.Kind = TSyntaxKind.AnonymousMethod then
        begin
          if Mentions(E, AHandle) then
          begin
            Exit(True);
          end;
          Continue;
        end;
        if E.Kind = TSyntaxKind.RoutineDecl then
        begin
          Continue;
        end;
        // [H] in einem Ausdruck (Handles := Handles + [H]): Das Handle landet in einem Array.
        if (E.Kind = TSyntaxKind.SetConstructor) and Mentions(E, AHandle) then
        begin
          Exit(True);
        end;
        if (E.Kind = TSyntaxKind.AssignStatement) and (E.ChildCount = 2) and IsHandleValue(E[1], AHandle) then
        begin
          Exit(True);
        end;
        // @Funktion := GetProcAddress(Modul, …) in eine Variable außerhalb der Routine: Das Modul muss geladen
        // bleiben, solange jemand den Zeiger aufrufen kann.
        if (E.Kind = TSyntaxKind.AssignStatement) and (E.ChildCount = 2) and (E[1].Kind = TSyntaxKind.Call) and
          SameRoutine(CallName(E[1]), 'GetProcAddress') and Mentions(E[1], AHandle) and
          not Contains(Locals, RootName(E[0])) then
        begin
          Exit(True);
        end;
        if (E.Kind = TSyntaxKind.InlineVar) and (E.ChildCount > 0) and IsHandleValue(E[E.ChildCount - 1], AHandle) then
        begin
          Exit(True);
        end;
        if (E.Kind = TSyntaxKind.WithStatement) and Mentions(E, AHandle) then
        begin
          Exit(True);
        end;
        if (E.Kind = TSyntaxKind.Call) and (E <> AOpenCall) then
        begin
          Name := CallName(E);
          if SameText(Name, 'Exit') or not (MatchText(Name, HandleUsers) or SameRoutine(Name, AHandle.CloseName) or
            MatchText(Name, ['Win32Check', 'CheckOSError', 'Assigned', 'Ord', 'Integer', 'Cardinal', 'NativeInt',
            'NativeUInt', 'THandle', 'IntToStr', 'IntToHex', 'Format'])) then
          begin
            for Index := 1 to E.ChildCount - 1 do
            begin
              if Mentions(E[Index], AHandle) then
              begin
                Exit(True);
              end;
            end;
          end;
        end;
        for Index := E.ChildCount - 1 downto 0 do
        begin
          Pending.Push(E[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function IsFailureValue(E: TSyntaxNode): Boolean;
  begin
    Result := ((E.Kind = TSyntaxKind.Literal) and MatchText(E.Name, ['0', 'nil'])) or
      ((E.Kind = TSyntaxKind.Identifier) and MatchText(E.Name, ['INVALID_HANDLE_VALUE', 'nil'])) or
      ((E.Kind = TSyntaxKind.Call) and (E.ChildCount = 2) and (E[1].Kind = TSyntaxKind.Literal) and
      (E[1].Name = '0'));
  end;

  // Bedeutet "E ist wahr", dass das Öffnen gelang (1), misslang (-1), oder ist es unklar (0)?
  // Wert eines Vergleichs mit dem Handle (H <> 0, RegOpenKeyEx(…) = ERROR_SUCCESS); 0 sonst.
  function ComparisonSuccess(E: TSyntaxNode; AOpenCall: TSyntaxNode; const AHandle: TOpenedHandle): Integer;
  var
    Index: Integer;
  begin
    Result := 0;
    if not MatchText(E.Name, ['=', '<>']) then
    begin
      Exit;
    end;
    for Index := 0 to 1 do
    begin
      if (SameText(PathOf(E[Index]), AHandle.Path) or (E[Index] = AOpenCall)) then
      begin
        // RegOpenKeyEx(…) = ERROR_SUCCESS
        if (E[1 - Index].Kind = TSyntaxKind.Identifier) and SameText(E[1 - Index].Name, 'ERROR_SUCCESS') then
        begin
          if E.Name = '=' then
          begin
            Exit(1);
          end;
          Exit(-1);
        end;
        if IsFailureValue(E[1 - Index]) then
        begin
          if E.Name = '=' then
          begin
            Exit(-1);
          end;
          Exit(1);
        end;
      end;
    end;
  end;

  function Success(ARoot: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Integer;
  var
    Pending: TStack<TSyntaxPostOrderEntry>;
    Values: TStack<Integer>;
    Entry: TSyntaxPostOrderEntry;
    E: TSyntaxNode;
    Value, Left, Right: Integer;
  begin
    // Iterativ (Bericht M1): Nachordnung mit Wertestapel; lange and/or-Ketten sind tiefe Bäume. Die Auswertung
    // hat keine Nebenwirkungen, daher darf sie ohne Kurzschluss beide Operanden berechnen.
    Pending := TStack<TSyntaxPostOrderEntry>.Create;
    Values := TStack<Integer>.Create;
    try
      Pending.Push(TSyntaxPostOrderEntry.Create(ARoot, False));
      while Pending.Count > 0 do
      begin
        Entry := Pending.Pop;
        E := Entry.Node;
        if Entry.Done then
        begin
          if E.Kind = TSyntaxKind.ParenExpr then
          begin
            Value := Values.Pop;
          end
          else if E.Kind = TSyntaxKind.UnaryExpr then
          begin
            Value := -Values.Pop;
          end
          else
          begin
            Right := Values.Pop;
            Left := Values.Pop;
            Value := 0;
            if SameText(E.Name, 'and') and ((Left > 0) or (Right > 0)) then
            begin
              Value := 1;
            end
            else if SameText(E.Name, 'or') and ((Left < 0) or (Right < 0)) then
            begin
              Value := -1;
            end;
          end;
          Values.Push(Value);
          Continue;
        end;
        Value := 0;
        if E.Kind = TSyntaxKind.ParenExpr then
        begin
          if E.ChildCount = 1 then
          begin
            Pending.Push(TSyntaxPostOrderEntry.Create(E, True));
            Pending.Push(TSyntaxPostOrderEntry.Create(E[0], False));
            Continue;
          end;
        end
        else if (E.Kind = TSyntaxKind.UnaryExpr) and SameText(E.Name, 'not') and (E.ChildCount = 1) then
        begin
          Pending.Push(TSyntaxPostOrderEntry.Create(E, True));
          Pending.Push(TSyntaxPostOrderEntry.Create(E[0], False));
          Continue;
        end
        // if CreateProcess(…) then, Win32Check(…)
        else if E = AOpenCall then
        begin
          Value := 1;
        end
        else if (E.Kind = TSyntaxKind.BinaryExpr) and (E.ChildCount = 2) then
        begin
          Value := ComparisonSuccess(E, AOpenCall, AHandle);
          if (Value = 0) and (SameText(E.Name, 'and') or SameText(E.Name, 'or')) then
          begin
            Pending.Push(TSyntaxPostOrderEntry.Create(E, True));
            Pending.Push(TSyntaxPostOrderEntry.Create(E[1], False));
            Pending.Push(TSyntaxPostOrderEntry.Create(E[0], False));
            Continue;
          end;
        end;
        Values.Push(Value);
      end;
      Result := Values.Pop;
    finally
      Values.Free;
      Pending.Free;
    end;
  end;

  function InRange(AInner, AOuter: TSyntaxNode): Boolean;
  begin
    Result := (AInner <> nil) and (AOuter <> nil) and (AInner.StartOffset >= AOuter.StartOffset) and
      (AInner.EndOffset <= AOuter.EndOffset);
  end;

  // Nachfolger, denen der Weg mit offenem Handle folgt: bei if über die Prüfung des Handles nur der Zweig, in
  // dem das Öffnen gelang.
  function Followed(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): TArray<TFlowNode>;
  var
    Next: TFlowNode;
    Condition, ThenPart: TSyntaxNode;
    Index, Verdict: Integer;
    IsThen: Boolean;
  begin
    Result := nil;
    Verdict := 0;
    ThenPart := nil;
    if (ANode.Kind = TFlowNodeKind.Condition) and (ANode.Syntax.Kind = TSyntaxKind.IfStatement) then
    begin
      Condition := nil;
      for Index := 0 to ANode.Syntax.ChildCount - 1 do
      begin
        if not (ANode.Syntax[Index].Kind in FlowStatementKinds) then
        begin
          if Condition = nil then
          begin
            Condition := ANode.Syntax[Index];
          end;
        end
        else if ThenPart = nil then
        begin
          ThenPart := ANode.Syntax[Index];
        end;
      end;
      if Condition <> nil then
      begin
        Verdict := Success(Condition, AHandle, AOpenCall);
      end;
    end;
    for Next in ANode.Successors do
    begin
      if ANode.IsImplicitRaiseEdge(Next) or (Next = Graph.RaiseExit) then
      begin
        Continue;
      end;
      if Verdict <> 0 then
      begin
        IsThen := (Next.Syntax <> nil) and InRange(Next.Syntax, ThenPart);
        if IsThen <> (Verdict > 0) then
        begin
          Continue;
        end;
      end;
      Result := Result + [Next];
    end;
  end;

  // Erreicht ein Weg vom Öffnen das normale Ende, ohne das Handle zu schließen oder weiterzugeben?
  function LeaksFrom(AOpen: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
  var
    Visited: TArray<Boolean>;
    Queue: TArray<TFlowNode>;
    Head: Integer;
    Current: TFlowNode;
    Part: TSyntaxNode;
    Stop: Boolean;
  begin
    Result := False;
    SetLength(Visited, Graph.Nodes.Count);
    Queue := Followed(AOpen, AHandle, AOpenCall);
    Head := 0;
    while Head < Length(Queue) do
    begin
      Current := Queue[Head];
      Inc(Head);
      if Visited[Current.Index] or (Current = AOpen) then
      begin
        Continue;
      end;
      Visited[Current.Index] := True;
      if Current = Graph.ExitNode then
      begin
        Exit(True);
      end;
      Stop := False;
      if Current.Syntax <> nil then
      begin
        for Part in Parts(Current) do
        begin
          if Closes(Part, AHandle) or PassesOn(Part, AHandle, AOpenCall) then
          begin
            Stop := True;
          end;
        end;
      end;
      // Neue Zuweisung an das Handle: das alte wird hier nicht weiter verfolgt.
      if not Stop and (Current.Syntax <> nil) and (Current.Syntax.Kind = TSyntaxKind.AssignStatement) and
        (Current.Syntax.ChildCount = 2) and SameText(PathOf(Current.Syntax[0]), AHandle.Path) then
      begin
        Stop := True;
      end;
      if Stop then
      begin
        Continue;
      end;
      Queue := Queue + Followed(Current, AHandle, AOpenCall);
    end;
  end;

  // Schließt die Routine das Handle irgendwo (im Rumpf, ohne eingebettete Routinen)?
  function ClosedAnywhere(ARoutine: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
  var
    Body: TSyntaxNode;
  begin
    Body := ARoutine.FindChild(TSyntaxKind.Block);
    Result := (Body <> nil) and Closes(Body, AHandle);
  end;

  // Einrückung vor ANode; False, wenn davor in der Zeile noch Code steht.
  function Indent(ANode: TSyntaxNode; out AIndent: string; out ALineStart: Integer): Boolean;
  var
    Start: Integer;
  begin
    Start := ANode.StartOffset;
    while (Start > 0) and CharInSet(AContext.Text[Start], [' ', #9]) do
    begin
      Dec(Start);
    end;
    AIndent := Copy(AContext.Text, Start + 1, ANode.StartOffset - Start);
    ALineStart := Start;
    Result := (Start = 0) or CharInSet(AContext.Text[Start], [#10, #13]);
  end;

  function PositionAt(AOffset: Integer): TTextPosition;
  var
    Index, Line, LineStart: Integer;
  begin
    Line := 0;
    LineStart := 0;
    for Index := 1 to AOffset do
    begin
      if AContext.Text[Index] = #10 then
      begin
        Inc(Line);
        LineStart := Index;
      end;
    end;
    Result := TTextPosition.Create(Line, AOffset - LineStart);
  end;

  // Korrektur: die Anweisungen nach dem Öffnen bis zum Ende ihres Blocks in try … finally Schließen end.
  function WrapFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>): TArray<TRuleFix>;
  var
    Block, First, Last: TSyntaxNode;
    Position, Index, LineStart: Integer;
    Outer, Body, Closing, Line: string;
    Lines: TArray<string>;
  begin
    Result := nil;
    Block := AStatement.Parent;
    if (Block = nil) or (Block.Kind <> TSyntaxKind.Block) then
    begin
      Exit;
    end;
    Position := -1;
    for Index := 0 to Block.ChildCount - 1 do
    begin
      if Block[Index] = AStatement then
      begin
        Position := Index;
      end;
    end;
    if Position < 0 then
    begin
      Exit;
    end;
    Closing := '';
    // Umgekehrte Reihenfolge: zuletzt geöffnet, zuerst geschlossen (PI.hThread vor PI.hProcess).
    for Index := High(AHandles) downto 0 do
    begin
      Closing := Closing + '%s  ' + AHandles[Index].CloseText + ';' + LineBreak;
    end;
    if not Indent(AStatement, Outer, LineStart) then
    begin
      Exit;
    end;
    Closing := StringReplace(Closing, '%s', Outer, [rfReplaceAll]);
    if Position = Block.ChildCount - 1 then
    begin
      // Nichts danach: nur das Schließen anhängen.
      Body := '';
      for Index := High(AHandles) downto 0 do
      begin
        Body := Body + ';' + LineBreak + Outer + AHandles[Index].CloseText;
      end;
      Result := [TRuleFix.Create(Format('%s ergänzen', [AHandles[0].CloseName]),
        [TRuleEdit.Create(TTextRange.Create(AStatement.EndPos, AStatement.EndPos), Body)])];
      Exit;
    end;
    First := Block[Position + 1];
    Last := Block[Block.ChildCount - 1];
    if (First.Kind = TSyntaxKind.EmptyStatement) or not Indent(First, Body, LineStart) then
    begin
      Exit;
    end;
    Body := '';
    Lines := Copy(AContext.Text, LineStart + 1, Last.EndOffset - LineStart).Replace(#13#10, #10).Split([#10]);
    for Line in Lines do
    begin
      if Trim(Line) = '' then
      begin
        Body := Body + LineBreak;
      end
      else
      begin
        Body := Body + '  ' + Line + LineBreak;
      end;
    end;
    // Die letzte Anweisung endet vor ihrem Semikolon; das alte Semikolon steht danach hinter end.
    if not Body.TrimRight.EndsWith(';') then
    begin
      Body := Body.TrimRight + ';' + LineBreak;
    end;
    Result := [TRuleFix.Create(Format('In try … finally %s einschließen', [AHandles[0].CloseName]),
      [TRuleEdit.Create(TTextRange.Create(PositionAt(LineStart), Last.EndPos),
      Outer + 'try' + LineBreak + Body + Outer + 'finally' + LineBreak + Closing + Outer + 'end')])];
  end;

  function CollectLocals(ARoutine: TSyntaxNode): TArray<string>;
  var
    Index: Integer;
    Name: string;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoutine);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if (E <> ARoutine) and (E.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
        begin
          Continue;
        end;
        if E.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
        begin
          for Name in E.Name.Split([',']) do
          begin
            Result := Result + [Trim(Name)];
          end;
        end;
        for Index := E.ChildCount - 1 downto 0 do
        begin
          Pending.Push(E[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Aufrufe in E, die Handles öffnen; ATarget ist das Ziel der Zuweisung.
  procedure CollectOpens(ARoot: TSyntaxNode; var ACalls: TArray<TSyntaxNode>; var ATargets: TArray<string>);
  var
    Index: Integer;
    Pair: THandlePair;
    E: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        E := Pending.Pop;
        if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
        begin
          Continue;
        end;
        if (E.Kind = TSyntaxKind.Call) and PairOf(CallName(E), Pair) then
        begin
          ACalls := ACalls + [E];
          ATargets := ATargets + [''];
        end;
        for Index := E.ChildCount - 1 downto 0 do
        begin
          Pending.Push(E[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Routine, Part, Statement: TSyntaxNode;
  Node: TFlowNode;
  Calls: TArray<TSyntaxNode>;
  Targets: TArray<string>;
  Handles, Leaked: TArray<TOpenedHandle>;
  Handle: TOpenedHandle;
  Index, First: Integer;
  Pair: string;
  Names, Message, Verb: string;
  Never: Boolean;
  Item: THandlePair;
  Fixes: TArray<TRuleFix>;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Table := nil;
  for Pair in Pairs(AContext.Options) do
  begin
    Item.Open := Copy(Pair, 1, Pos('|', Pair) - 1);
    Item.Where := Copy(Pair, Pos('|', Pair) + 1, MaxInt);
    Item.Close := Copy(Item.Where, Pos('|', Item.Where) + 1, MaxInt);
    Item.Where := Copy(Item.Where, 1, Pos('|', Item.Where) - 1);
    Table := Table + [Item];
  end;
  LineBreak := #10;
  if Pos(#13#10, AContext.Text) > 0 then
  begin
    LineBreak := #13#10;
  end;
  Cache := TRuleDerived.Open(AContext);
  for Routine in TRuleDerived.Routines(Cache, AContext) do
  begin
    Locals := CollectLocals(Routine);
    if Locals = nil then
    begin
      Continue;
    end;
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
    begin
      Continue;
    end;
    for Node in Graph.Nodes do
    begin
      if (Node.Syntax = nil) or not (Node.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) then
      begin
        Continue;
      end;
      Calls := nil;
      Targets := nil;
      // with: die Anweisungen darin sind eigene Knoten.
      if Node.Syntax.Kind = TSyntaxKind.WithStatement then
      begin
        Continue;
      end;
      for Part in Parts(Node) do
      begin
        First := Length(Calls);
        CollectOpens(Part, Calls, Targets);
        // H := CreateFile(…) bzw. var H := CreateFile(…): das Ziel nimmt das Handle auf.
        for Index := First to High(Calls) do
        begin
          if (Part.Kind = TSyntaxKind.AssignStatement) and (Part.ChildCount = 2) and (Calls[Index] = Part[1]) and
            (Part[0].Kind = TSyntaxKind.Identifier) then
          begin
            Targets[Index] := Part[0].Name;
          end
          else if (Part.Kind = TSyntaxKind.InlineVar) and (Calls[Index].Parent = Part) then
          begin
            Targets[Index] := Trim(Part.Name);
          end;
        end;
      end;
      for Index := 0 to High(Calls) do
      begin
        if not Opened(Calls[Index], Targets[Index], Handles) then
        begin
          Continue;
        end;
        Leaked := nil;
        Never := True;
        for Handle in Handles do
        begin
          if LeaksFrom(Node, Handle, Calls[Index]) then
          begin
            Leaked := Leaked + [Handle];
            Never := Never and not ClosedAnywhere(Routine, Handle);
          end;
        end;
        if Leaked = nil then
        begin
          Continue;
        end;
        Names := '';
        for Handle in Leaked do
        begin
          if Names <> '' then
          begin
            Names := Names + ' und ';
          end;
          Names := Names + Handle.Path;
        end;
        Verb := 'wird';
        if Length(Leaked) > 1 then
        begin
          Verb := 'werden';
        end;
        if Never then
        begin
          Message := Format('%s %s nie mit %s geschlossen (Handle-Leck).', [Names, Verb, Leaked[0].CloseName]);
        end
        else
        begin
          Message := Format('%s %s nicht auf jedem Weg mit %s geschlossen (Handle-Leck).',
            [Names, Verb, Leaked[0].CloseName]);
        end;
        Fixes := nil;
        Statement := Node.Syntax;
        if Never and (Node.Kind = TFlowNodeKind.Statement) and (Statement.StartPos.Line = Statement.EndPos.Line) then
        begin
          Fixes := WrapFix(Statement, Leaked);
        end;
        AReport.Add(NodeRange(Calls[Index]), Message, TRuleConfidence.Medium, Fixes);
      end;
    end;
  end;
end;

{ TOutParamReadRule }

function TOutParamReadRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OutParamReadRuleId, TRuleSeverity.Warning,
    'out-Parameter gelesen, bevor er gesetzt ist');
end;

/// <summary>Verwaltete Typen leert der Aufrufer vor dem Aufruf mit out.</summary>
function IsManagedParamType(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ManagedTypes) or MatchText(ATypeName, ['IInterface', 'IUnknown', 'TBytes']) or
    StartsText('TArray<', ATypeName) or StartsText('array of', ATypeName) or
    ((Length(ATypeName) > 1) and (ATypeName[1] = 'I') and CharInSet(ATypeName[2], ['A'..'Z']));
end;

/// <summary>Wird ein Teil von AName (AName.Feld, AName[I]) als Argument übergeben? Ein out-Argument
/// setzt ihn dann, ohne dass der Graph es sieht.</summary>
function PassesPart(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Continue;
      end;
      if Node.Kind = TSyntaxKind.Call then
      begin
        for Index := 1 to Node.ChildCount - 1 do
        begin
          if (Node[Index].Kind <> TSyntaxKind.Identifier) and SameText(RootName(Node[Index]), AName) then
          begin
            Exit(True);
          end;
        end;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TOutParamReadRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Routine, Header, Block, Params, Param: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Index: Integer;
  Name, TypeName: string;
  Reported: Boolean;

  function FlowNodeOf(ANode: TSyntaxNode): TFlowNode;
  begin
    Result := nil;
    while (ANode <> nil) and (Result = nil) do
    begin
      Result := Graph.NodeOf(ANode);
      ANode := ANode.Parent;
    end;
  end;

  function ShortOf(const AName: string): string;
  begin
    Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
  end;

  function Collapsed(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode <> nil then
    begin
      Result := LowerCase(StringReplace(StringReplace(StringReplace(Copy(AContext.Text, ANode.StartOffset + 1,
        ANode.EndOffset - ANode.StartOffset), ' ', '', [rfReplaceAll]), #13, '', [rfReplaceAll]), #10, '',
        [rfReplaceAll]));
    end;
  end;

  // Das Token "out" vor dem Parameter mit den Namen ANames in AParams.
  function OutToken(AParams: TSyntaxNode; const ANames: string; out AToken: TPascalToken): Boolean;
  var
    Inner, mIndex: Integer;
    Token: TPascalToken;
  begin
    Result := False;
    for Inner := 0 to AParams.ChildCount - 1 do
    begin
      if (AParams[Inner].Kind = TSyntaxKind.Parameter) and SameText(AParams[Inner].Name, ANames) and
        (AParams[Inner].Modifier = TParameterModifier.OutParam) then
      begin
        for mIndex := AContext.Tree.FirstTokenFrom(AParams[Inner].StartOffset) to High(AContext.Tree.Tokens) do
        begin
          Token := AContext.Tree.Tokens[mIndex];
          if Token.Offset >= AParams[Inner].EndOffset then
          begin
            Break;
          end;
          if (Token.Offset >= AParams[Inner].StartOffset) and SameText(Token.Text, 'out') then
          begin
            AToken := Token;
            Exit(True);
          end;
        end;
      end;
    end;
  end;

  // out -> var in der Implementierung und in jeder Deklaration mit gleicher Parameterliste.
  function Fix(const ANames: string): TArray<TRuleFix>;
  var
    Edits: TArray<TRuleEdit>;
    Token: TPascalToken;
    Key: string;
    Short: string;
    ClassPart: string;

    // Owner: Klasse, in deren Deklaration der Knoten steht ('' außerhalb).
    procedure Declarations(ARoot: TSyntaxNode);
    var
      Child: Integer;
      Node, Other: TSyntaxNode;
      Found: TPascalToken;
      Owner: string;
      Pending: TStack<TSyntaxNode>;
      PendingOwner: TStack<string>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      PendingOwner := TStack<string>.Create;
      try
        Pending.Push(ARoot);
        PendingOwner.Push('');
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          Owner := PendingOwner.Pop;
          if Node.Kind = TSyntaxKind.TypeDecl then
          begin
            Owner := Node.Name;
          end;
          if (Node.Kind = TSyntaxKind.RoutineHeader) and (Node <> Header) and SameText(ShortOf(Node.Name), Short) and
            SameText(Owner, ClassPart) then
          begin
            Other := Node.FindChild(TSyntaxKind.Parameters);
            if (Other <> nil) and (Collapsed(Other) = Key) and OutToken(Other, ANames, Found) then
            begin
              Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Found.StartPos, Found.EndPos), 'var')];
            end;
          end;
          // Rümpfe anderer Routinen enthalten keine Deklarationen dieser Routine.
          if Node.Kind = TSyntaxKind.Block then
          begin
            Continue;
          end;
          for Child := Node.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Node[Child]);
            PendingOwner.Push(Owner);
          end;
        end;
      finally
        PendingOwner.Free;
        Pending.Free;
      end;
    end;

  begin
    Result := nil;
    Edits := nil;
    Key := Collapsed(Params);
    Short := ShortOf(Routine.Name);
    ClassPart := Copy(Routine.Name, 1, Length(Routine.Name) - Length(Short) - 1);
    if Pos('<', ClassPart) > 0 then
    begin
      ClassPart := Copy(ClassPart, 1, Pos('<', ClassPart) - 1);
    end;
    // Deklarationen stehen vor der Implementierung; die Änderungen bleiben nach Stelle sortiert.
    Declarations(AContext.Tree.Root);
    if OutToken(Params, ANames, Token) then
    begin
      Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Token.StartPos, Token.EndPos), 'var')];
    end;
    if Edits <> nil then
    begin
      Result := [TRuleFix.Create('out durch var ersetzen', Edits)];
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode; const ANames: string);
  var
    Child: Integer;
    Node: TSyntaxNode;
    Flow: TFlowNode;
    Detail: string;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while (Pending.Count > 0) and not Reported do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        begin
          Continue;
        end;
        if IsName(Node, Name) and not ((Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.AssignStatement) and
          (Node.Parent.ChildCount > 0) and (Node.Parent[0] = Node)) then
        begin
          Flow := FlowNodeOf(Node);
          if (Flow <> nil) and (Graph.IsReachable(Flow) = TFlowAnswer.Yes) and
            Graph.ReachingDefinitions(Flow, Name).FromEntry then
          begin
            if IsManagedParamType(TypeName) then
            begin
              Detail := Format('bei %s ist er hier immer leer.', [TypeName]);
            end
            else
            begin
              Detail := 'sein Wert ist hier undefiniert.';
            end;
            AReport.Add(NodeRange(Node), Format('out-Parameter %s wird gelesen, bevor er gesetzt ist; %s',
              [Name, Detail]), TRuleConfidence.High, Fix(ANames));
            Reported := True;
            Exit;
          end;
        end;
        for Child := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Child]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Block := Routine.FindChild(TSyntaxKind.Block);
    Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
    if (Block = nil) or (Header = nil) then
    begin
      Continue;
    end;
    Params := Header.FindChild(TSyntaxKind.Parameters);
    if Params = nil then
    begin
      Continue;
    end;
    Graph := nil;
    for Index := 0 to Params.ChildCount - 1 do
    begin
      Param := Params[Index];
      if (Param.Kind <> TSyntaxKind.Parameter) or (Param.Modifier <> TParameterModifier.OutParam) then
      begin
        Continue;
      end;
      TypeName := '';
      if Param.FindChild(TSyntaxKind.TypeReference) <> nil then
      begin
        TypeName := Param.FindChild(TSyntaxKind.TypeReference).Name;
      end;
      for Name in Param.Name.Split([',']) do
      begin
        if HasOpaqueUse(Block, Name.Trim) or PassesPart(Block, Name.Trim) then
        begin
          Continue;
        end;
        if Graph = nil then
        begin
          Graph := TRuleDerived.Graph(Cache, AContext, Routine);
        end;
        if not Graph.Complete then
        begin
          Break;
        end;
        Reported := False;
        Visit(Block, Param.Name);
      end;
    end;
  end;
end;

{ TNoreturnReturnsRule }

type
  /// <summary>Was ein Aufruf für den Weg einer noreturn-Routine bedeutet.</summary>
  TNoreturnCallEffect = (Returns, Ends, Unknown);

/// <summary>AName ohne Typparameter (TListe&lt;T&gt;.Fehler -&gt; TListe.Fehler), klein geschrieben.</summary>
function WithoutTypeParams(const AName: string): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  for mIndex := 1 to Length(AName) do
  begin
    if AName[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AName[mIndex] = '>' then
    begin
      Dec(mDepth);
    end
    else if mDepth = 0 then
    begin
      Result := Result + AName[mIndex];
    end;
  end;
  Result := LowerCase(Result);
end;

function HasNoreturn(AHeader: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  if AHeader <> nil then
  begin
    for mIndex := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, 'noreturn') then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Voller Name eines Routinenkopfs: TKlasse.Name in einer Klassendeklaration, sonst der Name der
/// Routine (bei Methoden TKlasse.Name).</summary>
function HeaderFullName(AHeader: TSyntaxNode): string;
var
  mParent: TSyntaxNode;
begin
  if (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) then
  begin
    Exit(WithoutTypeParams(AHeader.Parent.Name));
  end;
  mParent := AHeader.Parent;
  while (mParent <> nil) and (mParent.Kind <> TSyntaxKind.TypeDecl) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent = nil then
  begin
    Result := WithoutTypeParams(AHeader.Name);
  end
  else
  begin
    Result := WithoutTypeParams(mParent.Name + '.' + AHeader.Name);
  end;
end;

/// <summary>Exit oder Exit(Wert) als eigene Anweisung (nicht TMonitor.Exit).</summary>
function IsExitStatement(ASyntax: TSyntaxNode): Boolean;
var
  mCallee: TSyntaxNode;
begin
  Result := False;
  if (ASyntax = nil) or (ASyntax.Kind <> TSyntaxKind.CallStatement) or (ASyntax.ChildCount = 0) then
  begin
    Exit;
  end;
  mCallee := ASyntax[0];
  if (mCallee.Kind = TSyntaxKind.Call) and (mCallee.ChildCount > 0) then
  begin
    mCallee := mCallee[0];
  end;
  Result := IsName(mCallee, 'Exit');
end;

function TNoreturnReturnsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(NoreturnReturnsRuleId, TRuleSeverity.Warning,
    'noreturn-Routine kann normal zurückkehren');
end;

procedure TNoreturnReturnsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mNoreturnFull, mNoreturnShort, mKnownShort: TDictionary<string, Boolean>;
  mCache: IRuleDerivedCache;
  mRoutine: TSyntaxNode;
  mGraph: TControlFlowGraph;
  mExits: TArray<TFlowNode>;
  mExit: TFlowNode;
  mToEnd: TArray<Boolean>;
  mName: string;

  procedure CollectHeaders;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mShort: string;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        for mIndex := 0 to mNode.ChildCount - 1 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
        if mNode.Kind <> TSyntaxKind.RoutineHeader then
        begin
          Continue;
        end;
        mShort := LowerCase(ShortName(HeaderFullName(mNode)));
        mKnownShort.AddOrSetValue(mShort, True);
        if HasNoreturn(mNode) then
        begin
          mNoreturnFull.AddOrSetValue(HeaderFullName(mNode), True);
          mNoreturnShort.AddOrSetValue(mShort, True);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  function IndexEffect(const AShort: string): TNoreturnCallEffect;
  var
    mLocation: TSymbolLocation;
  begin
    Result := TNoreturnCallEffect.Unknown;
    if AContext.Index = nil then
    begin
      Exit;
    end;
    for mLocation in AContext.Index.FindSymbols(AShort) do
    begin
      if mLocation.Symbol.HasDirective('noreturn') then
      begin
        Exit(TNoreturnCallEffect.Ends);
      end
      else
      begin
        Result := TNoreturnCallEffect.Returns;
      end;
    end;
  end;

  /// <summary>Wirkung der Anweisung ASyntax: Ends bei Halt, RunError und noreturn-Routinen, Unknown bei
  /// Aufrufen mit unbekanntem Ziel (inherited, Methoden fremder Typen ohne Index).</summary>
  function CallEffect(ASyntax: TSyntaxNode): TNoreturnCallEffect;
  var
    mCallee: TSyntaxNode;
    mShort: string;
    mMode: TFlowArgumentMode;
  begin
    Result := TNoreturnCallEffect.Returns;
    if (ASyntax = nil) or (ASyntax.Kind <> TSyntaxKind.CallStatement) or (ASyntax.ChildCount = 0) then
    begin
      Exit;
    end;
    mCallee := ASyntax[0];
    if (mCallee.Kind = TSyntaxKind.Call) and (mCallee.ChildCount > 0) then
    begin
      mCallee := mCallee[0];
    end;
    mShort := LowerCase(mCallee.Name);
    if mCallee.Kind = TSyntaxKind.Identifier then
    begin
      if MatchText(mShort, ['halt', 'runerror']) then
      begin
        Exit(TNoreturnCallEffect.Ends);
      end;
      // Sprünge modelliert der Graph selbst.
      if MatchText(mShort, ['exit', 'break', 'continue', 'abort']) then
      begin
        Exit;
      end;
    end
    else if mCallee.Kind <> TSyntaxKind.MemberAccess then
    begin
      Exit(TNoreturnCallEffect.Unknown);
    end;
    if mNoreturnShort.ContainsKey(mShort) then
    begin
      Exit(TNoreturnCallEffect.Ends);
    end;
    if mKnownShort.ContainsKey(mShort) or
      ((mCallee.Kind = TSyntaxKind.Identifier) and TFlowSignatures.TryBuiltin(mShort, 0, mMode)) then
    begin
      Exit;
    end;
    Result := IndexEffect(mShort);
  end;

  /// <summary>Knoten, die vom Anfang aus erreichbar sind, ohne einen Knoten zu verlassen, der den Weg
  /// beendet; von solchen Knoten führen nur die Ausnahmekanten weiter. Mit AStopAtExit enden die Wege auch
  /// an Exit.</summary>
  function Reachable(AStopAtExit: Boolean): TArray<Boolean>;
  var
    mPending: TStack<TFlowNode>;
    mNode, mNext: TFlowNode;
    mEnds: Boolean;
  begin
    SetLength(Result, mGraph.Nodes.Count);
    mPending := TStack<TFlowNode>.Create;
    try
      mPending.Push(mGraph.Entry);
      Result[mGraph.Entry.Index] := True;
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mEnds := (AStopAtExit and IsExitStatement(mNode.Syntax)) or
          (CallEffect(mNode.Syntax) <> TNoreturnCallEffect.Returns);
        for mNext in mNode.Successors do
        begin
          if not Result[mNext.Index] and (not mEnds or mNode.IsImplicitRaiseEdge(mNext)) then
          begin
            Result[mNext.Index] := True;
            mPending.Push(mNext);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  function ExitsReached: TArray<TFlowNode>;
  var
    mSeen: TArray<Boolean>;
    mNode: TFlowNode;
  begin
    Result := nil;
    mSeen := Reachable(False);
    for mNode in mGraph.Nodes do
    begin
      if mSeen[mNode.Index] and (mNode.Kind = TFlowNodeKind.Statement) and IsExitStatement(mNode.Syntax) then
      begin
        Result := Result + [mNode];
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'noreturn') then
  begin
    Exit;
  end;
  mNoreturnFull := TDictionary<string, Boolean>.Create;
  mNoreturnShort := TDictionary<string, Boolean>.Create;
  mKnownShort := TDictionary<string, Boolean>.Create;
  try
    CollectHeaders;
    mCache := TRuleDerived.Open(AContext);
    for mRoutine in TRuleDerived.Routines(mCache, AContext) do
    begin
      if not (HasNoreturn(mRoutine.FindChild(TSyntaxKind.RoutineHeader)) or
        mNoreturnFull.ContainsKey(WithoutTypeParams(mRoutine.Name))) then
      begin
        Continue;
      end;
      mGraph := TRuleDerived.Graph(mCache, AContext, mRoutine);
      if not mGraph.Complete then
      begin
        Continue;
      end;
      mName := ShortName(mRoutine.Name);
      mExits := ExitsReached;
      for mExit in mExits do
      begin
        AReport.Add(NodeRange(mExit.Syntax),
          Format('Exit verlässt %s normal, obwohl die Routine noreturn ist.', [mName]), TRuleConfidence.High);
      end;
      mToEnd := Reachable(True);
      if mToEnd[mGraph.ExitNode.Index] then
      begin
        AReport.Add(HeaderNameRange(AContext, mRoutine),
          Format('%s kann am Ende normal zurückkehren, obwohl die Routine noreturn ist.', [mName]),
          TRuleConfidence.High);
      end;
    end;
  finally
    mKnownShort.Free;
    mNoreturnShort.Free;
    mNoreturnFull.Free;
  end;
end;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TResultNotSetRule.Create);
  ARegistry.Register(TPossiblyUninitializedRule.Create);
  ARegistry.Register(TUnreachableCodeRule.Create);
  ARegistry.Register(TUseAfterFreeRule.Create);
  ARegistry.Register(TDerefBeforeNilCheckRule.Create);
  ARegistry.Register(TFieldFreeWithoutNilRule.Create);
  ARegistry.Register(TDestructorNotNilSafeRule.Create);
  ARegistry.Register(THandleLeakRule.Create);
  ARegistry.Register(TOutParamReadRule.Create);
  ARegistry.Register(TNoreturnReturnsRule.Create);
end;

end.
