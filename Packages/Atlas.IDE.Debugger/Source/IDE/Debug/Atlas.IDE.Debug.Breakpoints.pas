unit Atlas.IDE.Debug.Breakpoints;

// Vorübergehende Haltepunkte und Zustand des Debuggers für „Gezielt
// hineinspringen“ (#836) und „Beim nächsten Ereignis anhalten“ (#856):
// - Add legt einen Quelltext-Haltepunkt an, außer an einer Stelle, an der der
//   Benutzer schon einen hat (der bleibt, wie er ist, und hält ohnehin).
// - Mit Gruppe stehen sie in der Haltepunktliste zusammen (Atlas.Ereignis).
// - RemoveAll nimmt nur die eigenen wieder heraus.
// - Position liest den Ausführungspunkt eines Threads (Zeile ab 0).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI;

type
  TAtlasIdeBreakpoints = class
  public
    class function Debugger: IOTADebuggerServices; static;
    /// <summary>Laufender oder angehaltener Prozess; nil ohne.</summary>
    class function CurrentProcess: IOTAProcess; static;
    /// <summary>Angehaltener Prozess (auch nach Fehler oder Exception); nil sonst.</summary>
    class function StoppedProcess: IOTAProcess; static;
    class function IsStopped(const AProcess: IOTAProcess): Boolean; static;
    class function Position(const AThread: IOTAThread; out AFileName: string; out ALine: Integer): Boolean; static;
    /// <summary>Hat der Benutzer an AFileName/ALine (ab 0) schon einen Haltepunkt?</summary>
    class function Exists(const AFileName: string; ALine: Integer): Boolean; static;
    /// <summary>Neuer Haltepunkt an AFileName/ALine (ab 0); nil, wenn dort schon einer steht oder es nicht geht.
    /// </summary>
    class function Add(const AFileName: string; ALine: Integer): IOTABreakpoint; overload; static;
    /// <summary>Wie Add, dazu in der Haltepunktgruppe AGroup (in der Haltepunktliste der IDE sichtbar).</summary>
    class function Add(const AFileName: string; ALine: Integer; const AGroup: string): IOTABreakpoint; overload;
      static;
    /// <summary>Entfernt die Haltepunkte in ABreakpoints und leert die Liste.</summary>
    class procedure RemoveAll(var ABreakpoints: TArray<IOTABreakpoint>); static;
  end;

implementation

class function TAtlasIdeBreakpoints.Debugger: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeBreakpoints.CurrentProcess: IOTAProcess;
var
  mServices: IOTADebuggerServices;
begin
  Result := nil;
  mServices := Debugger;
  if (mServices <> nil) and (mServices.ProcessCount > 0) then
  begin
    Result := mServices.CurrentProcess;
  end;
end;

class function TAtlasIdeBreakpoints.IsStopped(const AProcess: IOTAProcess): Boolean;
begin
  Result := (AProcess <> nil) and (AProcess.ProcessState in [psStopped, psFault, psException]);
end;

class function TAtlasIdeBreakpoints.StoppedProcess: IOTAProcess;
begin
  Result := CurrentProcess;
  if not IsStopped(Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeBreakpoints.Position(const AThread: IOTAThread; out AFileName: string;
  out ALine: Integer): Boolean;
begin
  AFileName := '';
  ALine := -1;
  if AThread = nil then
  begin
    Exit(False);
  end;
  AFileName := AThread.CurrentFile;
  ALine := Integer(AThread.CurrentLine) - 1;
  Result := (AFileName <> '') and (ALine >= 0);
end;

class function TAtlasIdeBreakpoints.Exists(const AFileName: string; ALine: Integer): Boolean;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mExisting: IOTASourceBreakpoint;
begin
  Result := False;
  mServices := Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mExisting := mServices.SourceBkpts[mIndex];
    if (mExisting <> nil) and SameText(mExisting.FileName, AFileName) and (mExisting.LineNumber = ALine + 1) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasIdeBreakpoints.Add(const AFileName: string; ALine: Integer): IOTABreakpoint;
var
  mServices: IOTADebuggerServices;
begin
  Result := nil;
  mServices := Debugger;
  if (mServices = nil) or (AFileName = '') or (ALine < 0) or Exists(AFileName, ALine) then
  begin
    Exit;
  end;
  try
    Result := mServices.NewSourceBreakpoint(AFileName, ALine + 1, nil);
  except
    on Exception do
      Result := nil;
  end;
end;

class function TAtlasIdeBreakpoints.Add(const AFileName: string; ALine: Integer;
  const AGroup: string): IOTABreakpoint;
begin
  Result := Add(AFileName, ALine);
  if Result = nil then
  begin
    Exit;
  end;
  try
    Result.GroupName := AGroup;
  except
    // Ohne Gruppe hält der Haltepunkt genauso.
    on Exception do
      ;
  end;
end;

/// <summary>ABreakpoint entfernen; schon vom Benutzer gelöscht ist kein Fehler.</summary>
procedure RemoveQuietly(const AServices: IOTADebuggerServices; const ABreakpoint: IOTABreakpoint);
begin
  if ABreakpoint = nil then
  begin
    Exit;
  end;
  try
    AServices.RemoveBreakpoint(ABreakpoint);
  except
    // Schon vom Benutzer gelöscht: nichts mehr zu tun.
    on Exception do
      ;
  end;
end;

class procedure TAtlasIdeBreakpoints.RemoveAll(var ABreakpoints: TArray<IOTABreakpoint>);
var
  mServices: IOTADebuggerServices;
  mBreakpoint: IOTABreakpoint;
begin
  mServices := Debugger;
  try
    if mServices <> nil then
    begin
      for mBreakpoint in ABreakpoints do
      begin
        RemoveQuietly(mServices, mBreakpoint);
      end;
    end;
  finally
    ABreakpoints := nil;
  end;
end;

end.
