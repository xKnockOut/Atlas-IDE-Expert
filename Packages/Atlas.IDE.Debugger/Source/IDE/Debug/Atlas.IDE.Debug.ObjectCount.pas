unit Atlas.IDE.Debug.ObjectCount;

// Objektzählung im Fenster „Atlas: Speicher“ (#858, experimentell, debug.memoryTimeline.objectCount):
// „Objekte zählen“ liest im angehaltenen Programm den Speicher (TAtlasIdeProcessMemory) und zählt lebende Objekte
// je Klasse (TAtlasObjectCounter). Jede Zählung wird mit der vorigen derselben Sitzung verglichen; eine neue
// Sitzung beginnt ohne Basis. Gezählt wird im Hauptthread, während das Programm steht; das dauert je nach
// Speicher Bruchteile einer Sekunde bis wenige Sekunden (Sanduhr). Kein Zeitgeber, kein Thread: Nach Release
// erreicht nichts mehr das Modul. Nur im Hauptthread.

interface

uses
  Atlas.Core.Debug.ObjectCount,
  Atlas.UI.Debug.ObjectCountPanel;

type
  TAtlasIdeDebugObjectCount = class
  private type
    TCounts = record
      Base: TAtlasObjectCount;
      Current: TAtlasObjectCount;
      HasBase: Boolean;
      HasCurrent: Boolean;
    end;
  private class var
    FCounts: TCounts;
    class function Panel: TAtlasDebugObjectCountPanel; static;
    class procedure Count; static;
  public
    /// <summary>Bereich im Frame verdrahten und nach der Einstellung zeigen oder verbergen.</summary>
    class procedure Wire(APanel: TAtlasDebugObjectCountPanel); static;
    /// <summary>Neue Debug-Sitzung: Zählungen verwerfen.</summary>
    class procedure Reset; static;
    /// <summary>Knopf „Objekte zählen“.</summary>
    class procedure CountNow; static;
    /// <summary>Beim Abmelden: Ereignis lösen und Zählungen verwerfen.</summary>
    class procedure Release(APanel: TAtlasDebugObjectCountPanel); static;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.ObjectCountReader,
  Atlas.IDE.Debug.MemoryWindow,
  Atlas.UI.Debug.MemoryFrame,
  Atlas.UI.Debug.Memory.Strings;

class function TAtlasIdeDebugObjectCount.Panel: TAtlasDebugObjectCountPanel;
var
  mFrame: TAtlasDebugMemoryFrame;
begin
  Result := nil;
  mFrame := TAtlasIdeDebugMemoryWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    Result := mFrame.ObjectCount;
  end;
end;

class procedure TAtlasIdeDebugObjectCount.Wire(APanel: TAtlasDebugObjectCountPanel);
begin
  if APanel = nil then
  begin
    Exit;
  end;
  APanel.OnCount := CountNow;
  if FCounts.HasCurrent then
  begin
    APanel.SetCounts(FCounts.Base, FCounts.Current, FCounts.HasBase);
  end;
end;

class procedure TAtlasIdeDebugObjectCount.Reset;
var
  mPanel: TAtlasDebugObjectCountPanel;
begin
  FCounts := Default(TCounts);
  mPanel := Panel;
  if mPanel <> nil then
  begin
    mPanel.ClearCounts;
  end;
end;

class procedure TAtlasIdeDebugObjectCount.Release(APanel: TAtlasDebugObjectCountPanel);
begin
  if APanel <> nil then
  begin
    APanel.OnCount := nil;
  end;
  FCounts := Default(TCounts);
end;

class procedure TAtlasIdeDebugObjectCount.CountNow;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, Count);
end;

class procedure TAtlasIdeDebugObjectCount.Count;
var
  mPanel: TAtlasDebugObjectCountPanel;
  mMemory: IAtlasProcessMemory;
  mError: string;
  mCounter: TAtlasObjectCounter;
  mPid: Cardinal;
  mCursor: TCursor;
begin
  mPanel := Panel;
  if (mPanel = nil) or not TAtlasIdeSettings.Current.DebugMemoryTimelineObjectCount then
  begin
    Exit;
  end;
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    mPanel.ShowStatus(TAtlasMemoryStrings.Text(TAtlasMemoryTextId.ObjectCountNotStopped));
    Exit;
  end;
  mPid := TAtlasIdeDebugSession.Process.ProcessId;
  if not TAtlasIdeProcessMemory.Open(mPid, mMemory, mError) then
  begin
    mPanel.ShowStatus(TAtlasMemoryStrings.Fmt(TAtlasMemoryTextId.ObjectCountNoAccess, [mPid, mError]));
    Exit;
  end;
  FCounts.HasBase := FCounts.HasCurrent;
  if FCounts.HasBase then
  begin
    FCounts.Base := FCounts.Current;
  end;
  mCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  mCounter := TAtlasObjectCounter.Create(mMemory);
  try
    FCounts.Current := mCounter.Run;
    FCounts.HasCurrent := True;
  finally
    mCounter.Free;
    Screen.Cursor := mCursor;
  end;
  mPanel.SetCounts(FCounts.Base, FCounts.Current, FCounts.HasBase);
end;

end.
