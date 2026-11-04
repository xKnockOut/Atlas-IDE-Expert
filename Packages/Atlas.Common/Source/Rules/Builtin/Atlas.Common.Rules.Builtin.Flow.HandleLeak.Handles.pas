unit Atlas.Common.Rules.Builtin.Flow.HandleLeak.Handles;

// Handles für handle-leak (Atlas.Common.Rules.Builtin.Flow.HandleLeak, #269): Tabelle der Paare aus Öffnen und
// Schließen, Option pairs, und die Auswertung von Ausdrücken für ein geöffnetes Handle: Schließen, Weitergabe,
// Erfolg des Öffnens in einer Bedingung.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

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

/// <summary>Paare "Öffnen|Ort|Schließen" aus der Tabelle und der Option pairs ("Öffnen&gt;Schließen" oder
/// {"open", "close"}).</summary>
function HandlePairs(const AOptions: string): TArray<string>;
/// <summary>Zerlegt Paare "Öffnen|Ort|Schließen".</summary>
function HandleTable(const APairs: TArray<string>): TArray<THandlePair>;
/// <summary>Name einer aufgerufenen Routine ohne Unit-Präfix (Winapi.Windows.CloseHandle); '' ohne.</summary>
function CallName(const AText: string; ACall: TSyntaxNode): string;
/// <summary>Gleicher Name, auch mit A/W-Endung (CreateFileW).</summary>
function SameRoutine(const AName, ATableName: string): Boolean;
/// <summary>Pfad eines Ausdrucks: H, PI.hProcess; sonst ''.</summary>
function HandlePath(ANode: TSyntaxNode): string;
/// <summary>Schließt ARoot das Handle (CloseHandle(PI.hProcess), ReleaseDC(Wnd, DC))?</summary>
function ClosesHandle(const AText: string; ARoot: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
/// <summary>Kommt das Handle (oder seine Wurzel) unter ARoot vor?</summary>
function MentionsHandle(ARoot: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
/// <summary>Gibt ARoot das Handle weiter: Zuweisung an ein anderes Ziel, Exit(H), Übergabe an eine unbekannte
/// Routine, with, anonyme Methode? ALocals: lokale Variablen der Routine.</summary>
function PassesOn(const AText: string; ARoot: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode;
  const ALocals: TArray<string>): Boolean;
/// <summary>Bedeutet "ARoot ist wahr", dass das Öffnen gelang (1), misslang (-1), oder ist es unklar (0)?</summary>
function OpenSuccess(ARoot: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Integer;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Rules.Builtin.Flow.Shared;

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

  /// <summary>Aufrufe, die ein Handle nur prüfen, umwandeln oder ausgeben.</summary>
  NeutralCalls: array[0..11] of string = ('Win32Check', 'CheckOSError', 'Assigned', 'Ord', 'Integer', 'Cardinal',
    'NativeInt', 'NativeUInt', 'THandle', 'IntToStr', 'IntToHex', 'Format');
  /// <summary>Units, deren Präfix vor einem Aufruf stehen darf.</summary>
  ApiUnits: array[0..7] of string = ('Windows', 'Winapi.Windows', 'ShellAPI', 'Winapi.ShellAPI', 'TlHelp32',
    'Winapi.TlHelp32', 'WinSvc', 'Winapi.WinSvc');

/// <summary>Ein Eintrag der Option pairs als "Öffnen|r|Schließen(%h)"; '' bei ungültigem Eintrag.</summary>
function OptionPair(AItem: TJSONValue): string;
var
  Open, Close: string;
begin
  Result := '';
  Open := '';
  Close := '';
  // "MeinOeffnen>MeinSchliessen" bzw. {"open": "MeinOeffnen", "close": "MeinSchliessen"}.
  if (AItem is TJSONString) and (Pos('>', AItem.Value) > 1) then
  begin
    Open := Trim(Copy(AItem.Value, 1, Pos('>', AItem.Value) - 1));
    Close := Trim(Copy(AItem.Value, Pos('>', AItem.Value) + 1, MaxInt));
  end
  else if (AItem is TJSONObject) and TJSONObject(AItem).TryGetValue<string>('open', Open) and
    TJSONObject(AItem).TryGetValue<string>('close', Close) then
  begin
    Open := Trim(Open);
    Close := Trim(Close);
  end;
  if (Open <> '') and (Close <> '') and IsValidIdent(Open, True) and IsValidIdent(Close, True) then
  begin
    Result := Open + '|r|' + Close + '(%h)';
  end;
end;

/// <summary>Gültige Einträge der Liste AList (TJSONArray); sonst keine.</summary>
function OptionPairs(AList: TJSONValue): TArray<string>;
var
  Item: TJSONValue;
  Pair: string;
begin
  Result := nil;
  if not (AList is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(AList) do
  begin
    Pair := OptionPair(Item);
    if Pair <> '' then
    begin
      Result := Result + [Pair];
    end;
  end;
end;

function HandlePairs(const AOptions: string): TArray<string>;
var
  Value: TJSONValue;
  Pair: string;
begin
  Result := nil;
  for Pair in BuiltinHandlePairs do
  begin
    Result := Result + [Pair];
  end;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if Value is TJSONObject then
    begin
      Result := Result + OptionPairs(TJSONObject(Value).GetValue('pairs'));
    end;
  finally
    Value.Free;
  end;
end;

function HandleTable(const APairs: TArray<string>): TArray<THandlePair>;
var
  Pair: string;
  Item: THandlePair;
begin
  Result := nil;
  for Pair in APairs do
  begin
    Item.Open := Copy(Pair, 1, Pos('|', Pair) - 1);
    Item.Where := Copy(Pair, Pos('|', Pair) + 1, MaxInt);
    Item.Close := Copy(Item.Where, Pos('|', Item.Where) + 1, MaxInt);
    Item.Where := Copy(Item.Where, 1, Pos('|', Item.Where) - 1);
    Result := Result + [Item];
  end;
end;

function CallName(const AText: string; ACall: TSyntaxNode): string;
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
    MatchText(Trim(SourceText(AText, Callee[0])), ApiUnits) then
  begin
    Result := Callee.Name;
  end;
end;

function SameRoutine(const AName, ATableName: string): Boolean;
begin
  Result := SameText(AName, ATableName) or ((Length(AName) = Length(ATableName) + 1) and
    StartsText(ATableName, AName) and CharInSet(AName[Length(AName)], ['A', 'W']));
end;

function HandlePath(ANode: TSyntaxNode): string;
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

/// <summary>Steht APath unter den Argumenten des Aufrufs ACall?</summary>
function PassesHandlePath(ACall: TSyntaxNode; const APath: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result or SameText(HandlePath(ACall[Index]), APath);
  end;
end;

function ClosesHandle(const AText: string; ARoot: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
var
  Text: string;
  Handle: TOpenedHandle;
begin
  Text := AText;
  Handle := AHandle;
  // Iterativ (Bericht M1).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.Call) and SameRoutine(CallName(Text, ANode), Handle.CloseName) and
        PassesHandlePath(ANode, Handle.Path) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Bezeichner, der nicht vorn in einem Zugriff X.Feld steht.</summary>
function IsPlainUse(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Parent = nil) or (ANode.Parent.Kind <> TSyntaxKind.MemberAccess) or (ANode.Parent[0] <> ANode);
end;

/// <summary>Ist ANode die Wurzel des Handles, und zwar als Ganzes oder vor dem Feld des Handles?</summary>
function MentionedHere(ANode: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AHandle.Root);
  Result := Result and (IsPlainUse(ANode) or SameText(HandlePath(ANode.Parent), AHandle.Path) or
    (Pos('.', AHandle.Path) = 0));
end;

function MentionsHandle(ARoot: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
var
  Handle: TOpenedHandle;
begin
  Handle := AHandle;
  // Iterativ (Bericht M1).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if MentionedHere(ANode, Handle) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Ist E das Handle selbst, seine Wurzel (PI) oder eine Typumwandlung davon (THandle(H), (H))?</summary>
function IsHandleValue(E: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
begin
  // Iterativ (Bericht M1): an Klammern und Typumwandlungen entlang nach innen.
  Result := False;
  while True do
  begin
    if SameText(HandlePath(E), AHandle.Path) or ((E.Kind = TSyntaxKind.Identifier) and SameText(E.Name, AHandle.Root)) then
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

/// <summary>H := Handle bzw. var X := Handle: Das Handle landet in einem anderen Ziel.</summary>
function AssignsHandle(ANode: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
    IsHandleValue(ANode[1], AHandle);
  Result := Result or ((ANode.Kind = TSyntaxKind.InlineVar) and (ANode.ChildCount > 0) and
    IsHandleValue(ANode[ANode.ChildCount - 1], AHandle));
end;

/// <summary>@Funktion := GetProcAddress(Modul, …) in eine Variable außerhalb der Routine: Das Modul muss geladen
/// bleiben, solange jemand den Zeiger aufrufen kann.</summary>
function ExportsProcAddress(const AText: string; ANode: TSyntaxNode; const AHandle: TOpenedHandle;
  const ALocals: TArray<string>): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
    (ANode[1].Kind = TSyntaxKind.Call);
  Result := Result and SameRoutine(CallName(AText, ANode[1]), 'GetProcAddress') and
    MentionsHandle(ANode[1], AHandle) and not MatchText(RootName(ANode[0]), ALocals);
end;

/// <summary>Benutzt die Routine AName das Handle nur, ohne es zu übernehmen?</summary>
function IsHandleUser(const AName: string; const AHandle: TOpenedHandle): Boolean;
begin
  Result := MatchText(AName, HandleUsers) or SameRoutine(AName, AHandle.CloseName) or
    MatchText(AName, NeutralCalls);
end;

function MentionedInArguments(ACall: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result or MentionsHandle(ACall[Index], AHandle);
  end;
end;

/// <summary>Übergabe an Exit oder an eine Routine, die das Handle übernehmen kann.</summary>
function HandsToCall(const AText: string; ACall: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
var
  Name: string;
begin
  Name := CallName(AText, ACall);
  Result := SameText(Name, 'Exit') or not IsHandleUser(Name, AHandle);
  Result := Result and MentionedInArguments(ACall, AHandle);
end;

/// <summary>Gibt ANode selbst das Handle weiter? [H] in einem Ausdruck (Handles := Handles + [H]) legt es in ein
/// Array, with H do … gibt es an den Rumpf.</summary>
function PassesHere(const AText: string; ANode: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode;
  const ALocals: TArray<string>): Boolean;
begin
  Result := (ANode.Kind in [TSyntaxKind.SetConstructor, TSyntaxKind.WithStatement]) and
    MentionsHandle(ANode, AHandle);
  Result := Result or AssignsHandle(ANode, AHandle) or ExportsProcAddress(AText, ANode, AHandle, ALocals);
  Result := Result or ((ANode.Kind = TSyntaxKind.Call) and (ANode <> AOpenCall) and
    HandsToCall(AText, ANode, AHandle));
end;

function PassStep(const AText: string; ANode: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode;
  const ALocals: TArray<string>): TSyntaxSearchStep;
begin
  Result := TSyntaxSearchStep.Descend;
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
  begin
    Result := TSyntaxSearchStep.Skip;
    if MentionsHandle(ANode, AHandle) then
    begin
      Result := TSyntaxSearchStep.Found;
    end;
  end
  else if ANode.Kind = TSyntaxKind.RoutineDecl then
  begin
    Result := TSyntaxSearchStep.Skip;
  end
  else if PassesHere(AText, ANode, AHandle, AOpenCall, ALocals) then
  begin
    Result := TSyntaxSearchStep.Found;
  end;
end;

function PassesOn(const AText: string; ARoot: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode;
  const ALocals: TArray<string>): Boolean;
var
  Text: string;
  Handle: TOpenedHandle;
  OpenCall: TSyntaxNode;
  Locals: TArray<string>;
begin
  Text := AText;
  Handle := AHandle;
  OpenCall := AOpenCall;
  Locals := ALocals;
  // Iterativ (Bericht M1).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := PassStep(Text, ANode, Handle, OpenCall, Locals);
    end) <> nil;
end;

function IsFailureValue(ANode: TSyntaxNode): Boolean;
begin
  if ANode.Kind = TSyntaxKind.Literal then
  begin
    Result := MatchText(ANode.Name, ['0', 'nil']);
  end
  else if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := MatchText(ANode.Name, ['INVALID_HANDLE_VALUE', 'nil']);
  end
  else
  begin
    Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
      (ANode[1].Kind = TSyntaxKind.Literal) and (ANode[1].Name = '0');
  end;
end;

/// <summary>Wert eines Vergleichs "geöffneter Wert = AOther" (AEquals) bzw. "&lt;&gt; AOther".</summary>
function ComparedVerdict(AOther: TSyntaxNode; AEquals: Boolean): Integer;
begin
  Result := 0;
  // RegOpenKeyEx(…) = ERROR_SUCCESS
  if (AOther.Kind = TSyntaxKind.Identifier) and SameText(AOther.Name, 'ERROR_SUCCESS') then
  begin
    Result := 1;
  end
  else if IsFailureValue(AOther) then
  begin
    Result := -1;
  end;
  if not AEquals then
  begin
    Result := -Result;
  end;
end;

function IsOpenedValue(ANode, AOpenCall: TSyntaxNode; const AHandle: TOpenedHandle): Boolean;
begin
  Result := SameText(HandlePath(ANode), AHandle.Path) or (ANode = AOpenCall);
end;

/// <summary>Wert eines Vergleichs mit dem Handle (H &lt;&gt; 0, RegOpenKeyEx(…) = ERROR_SUCCESS); 0 sonst.</summary>
function ComparisonSuccess(ANode, AOpenCall: TSyntaxNode; const AHandle: TOpenedHandle): Integer;
var
  Index: Integer;
begin
  Result := 0;
  if not MatchText(ANode.Name, ['=', '<>']) then
  begin
    Exit;
  end;
  for Index := 0 to 1 do
  begin
    if (Result = 0) and IsOpenedValue(ANode[Index], AOpenCall, AHandle) then
    begin
      Result := ComparedVerdict(ANode[1 - Index], ANode.Name = '=');
    end;
  end;
end;

/// <summary>and ist erfolgreich, wenn ein Teil es ist; or misslingt, wenn ein Teil misslingt.</summary>
function JunctionSuccess(const AOperator: string; ALeft, ARight: Integer): Integer;
begin
  Result := 0;
  if SameText(AOperator, 'and') and ((ALeft > 0) or (ARight > 0)) then
  begin
    Result := 1;
  end
  else if SameText(AOperator, 'or') and ((ALeft < 0) or (ARight < 0)) then
  begin
    Result := -1;
  end;
end;

/// <summary>Fasst die Werte der Teile von ANode zusammen; sie liegen oben auf AValues.</summary>
function CombinedSuccess(ANode: TSyntaxNode; AValues: TStack<Integer>): Integer;
var
  Left, Right: Integer;
begin
  if ANode.Kind = TSyntaxKind.ParenExpr then
  begin
    Result := AValues.Pop;
  end
  else if ANode.Kind = TSyntaxKind.UnaryExpr then
  begin
    Result := -AValues.Pop;
  end
  else
  begin
    Right := AValues.Pop;
    Left := AValues.Pop;
    Result := JunctionSuccess(ANode.Name, Left, Right);
  end;
end;

/// <summary>(X) und not X: der Wert des einen Teils, bei not umgekehrt.</summary>
function IsWrapper(ANode: TSyntaxNode): Boolean;
begin
  Result := ((ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1)) or
    ((ANode.Kind = TSyntaxKind.UnaryExpr) and SameText(ANode.Name, 'not') and (ANode.ChildCount = 1));
end;

procedure EnterSuccess(ANode: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode;
  APending: TStack<TSyntaxPostOrderEntry>; AValues: TStack<Integer>);
var
  Value: Integer;
begin
  if IsWrapper(ANode) then
  begin
    APending.Push(TSyntaxPostOrderEntry.Create(ANode, True));
    APending.Push(TSyntaxPostOrderEntry.Create(ANode[0], False));
    Exit;
  end;
  Value := 0;
  // if CreateProcess(…) then, Win32Check(…)
  if ANode = AOpenCall then
  begin
    Value := 1;
  end
  else if (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.ChildCount = 2) then
  begin
    Value := ComparisonSuccess(ANode, AOpenCall, AHandle);
    if (Value = 0) and MatchText(ANode.Name, ['and', 'or']) then
    begin
      APending.Push(TSyntaxPostOrderEntry.Create(ANode, True));
      APending.Push(TSyntaxPostOrderEntry.Create(ANode[1], False));
      APending.Push(TSyntaxPostOrderEntry.Create(ANode[0], False));
      Exit;
    end;
  end;
  AValues.Push(Value);
end;

function OpenSuccess(ARoot: TSyntaxNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Integer;
var
  Pending: TStack<TSyntaxPostOrderEntry>;
  Values: TStack<Integer>;
  Entry: TSyntaxPostOrderEntry;
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
      if Entry.Done then
      begin
        Values.Push(CombinedSuccess(Entry.Node, Values));
      end
      else
      begin
        EnterSuccess(Entry.Node, AHandle, AOpenCall, Pending, Values);
      end;
    end;
    Result := Values.Pop;
  finally
    Values.Free;
    Pending.Free;
  end;
end;

end.
