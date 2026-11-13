unit Atlas.IDE.Debug.ThreadFreeze;

// Threads einfrieren (#852, experimentell): Die ToolsAPI kann einzelne Threads nicht anhalten. Atlas öffnet den
// Thread des Programms mit OpenThread(THREAD_SUSPEND_RESUME) und hält ihn mit SuspendThread an; beim Fortsetzen läuft
// er nicht weiter, bis ResumeThread ihn auftaut. Das Handle bleibt offen, solange der Thread eingefroren ist.
//   - Geht nur, wenn das Programm auf diesem Rechner läuft (nicht beim Remote-Debuggen).
//   - Release taut alle Threads auf (Ende der Sitzung, Abschalten, Entladen).
// Windows-Aufrufe stehen hier und nicht in Atlas.Windows: Das Plugin requiret nur Base, Base nicht Atlas.Windows.
// Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Debug.ThreadMarks;

type
  TAtlasIdeDebugThreadFreeze = class
  private type
    THandles = TArray<THandle>;
  private class var
    FFrozen: TAtlasDebugThreadSet;
    /// <summary>Handle je Eintrag von FFrozen, in derselben Reihenfolge.</summary>
    FHandles: THandles;
    class function IndexOf(AThreadId: Cardinal): Integer; static;
  public
    /// <summary>Thread AThreadId einfrieren; False, wenn Windows ihn nicht anhalten kann.</summary>
    class function Freeze(AThreadId: Cardinal): Boolean; static;
    /// <summary>Thread AThreadId auftauen; False, wenn er nicht eingefroren war.</summary>
    class function Thaw(AThreadId: Cardinal): Boolean; static;
    /// <summary>Alle eingefrorenen Threads auftauen.</summary>
    class procedure ThawAll; static;
    class function IsFrozen(AThreadId: Cardinal): Boolean; static;
    class function Count: Integer; static;
    class function Frozen: TAtlasDebugThreadSet; static;
    class procedure Release; static;
  end;

implementation

uses
  Winapi.Windows;

{ TAtlasIdeDebugThreadFreeze }

class function TAtlasIdeDebugThreadFreeze.IndexOf(AThreadId: Cardinal): Integer;
var
  mIndex: Integer;
  mIds: TArray<Cardinal>;
begin
  mIds := FFrozen.Ids;
  for mIndex := 0 to High(mIds) do
  begin
    if mIds[mIndex] = AThreadId then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasIdeDebugThreadFreeze.Freeze(AThreadId: Cardinal): Boolean;
var
  mHandle: THandle;
begin
  Result := FFrozen.Contains(AThreadId);
  if Result then
  begin
    Exit;
  end;
  mHandle := OpenThread(THREAD_SUSPEND_RESUME, False, AThreadId);
  if mHandle = 0 then
  begin
    Exit;
  end;
  if SuspendThread(mHandle) = DWORD(-1) then
  begin
    CloseHandle(mHandle);
    Exit;
  end;
  FFrozen.Add(AThreadId);
  FHandles := FHandles + [mHandle];
  Result := True;
end;

class function TAtlasIdeDebugThreadFreeze.Thaw(AThreadId: Cardinal): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AThreadId);
  Result := mIndex >= 0;
  if not Result then
  begin
    Exit;
  end;
  // Ist der Thread inzwischen beendet, scheitert ResumeThread; das Handle wird trotzdem geschlossen.
  ResumeThread(FHandles[mIndex]);
  CloseHandle(FHandles[mIndex]);
  Delete(FHandles, mIndex, 1);
  FFrozen.Remove(AThreadId);
end;

class procedure TAtlasIdeDebugThreadFreeze.ThawAll;
var
  mId: Cardinal;
begin
  for mId in FFrozen.Ids do
  begin
    Thaw(mId);
  end;
  FFrozen.Clear;
  FHandles := nil;
end;

class function TAtlasIdeDebugThreadFreeze.IsFrozen(AThreadId: Cardinal): Boolean;
begin
  Result := FFrozen.Contains(AThreadId);
end;

class function TAtlasIdeDebugThreadFreeze.Count: Integer;
begin
  Result := FFrozen.Count;
end;

class function TAtlasIdeDebugThreadFreeze.Frozen: TAtlasDebugThreadSet;
begin
  Result := FFrozen;
end;

class procedure TAtlasIdeDebugThreadFreeze.Release;
begin
  ThawAll;
end;

end.
