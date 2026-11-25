unit Atlas.IDE.Tracker.Attach.Sources;

// Quellen des Dialogs „An Issue anhängen …“ (#1276), die aus der IDE kommen:
// - das Bild des Formulars bzw. Frames im Designer des aktiven Moduls
//   (GetFormImage bzw. PaintTo; nil bei Datenmodul, FMX oder ohne Designer),
// - aus dem Bericht des Debuggers (#1455, über die Registry der Module): der
//   debuggte Prozess, das gestartete Projekt, die Debug-Notiz (#582) und der
//   Exception-Verlauf (#517).
// Ohne Modul, das eine Debug-Sitzung kennt, liefern die Abfragen leere Werte.

interface

uses
  Vcl.Graphics;

type
  TAtlasIdeAttachSources = record
  public const
    /// <summary>Höchstens so viele Einträge des Exception-Verlaufs.</summary>
    cMaxExceptions = 20;
  public
    /// <summary>Bild des Formulars bzw. Frames im Designer des aktiven Moduls mit seinem Namen; nil ohne. Der
    /// Aufrufer gibt das Bild frei.</summary>
    class function DesignerImage(out AName: string): TBitmap; static;
    /// <summary>Kennung des debuggten Prozesses; 0 ohne.</summary>
    class function ProcessId: Cardinal; static;
    /// <summary>Beim Debuggen das gestartete Projekt; '' ohne.</summary>
    class function LaunchProject: string; static;
    /// <summary>Debug-Notiz des aktuellen Halts mit Dateiname; False, wenn das Programm nicht angehalten ist oder
    /// kein Modul eine Debug-Sitzung kennt.</summary>
    class function DebugNote(out AMarkdown, AFileName: string): Boolean; static;
    /// <summary>Exception-Verlauf der Sitzung als Text, neueste zuerst; '' ohne Einträge.</summary>
    class function ExceptionsText(out ACount: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Modules.Registry,
  Atlas.IDE.Contracts.DebugReport;

/// <summary>Bild eines Formulars bzw. Frames im Designer; nil ohne Fenster.</summary>
function RootImage(ARoot: TComponent): TBitmap;
begin
  Result := nil;
  if ARoot is TCustomForm then
  begin
    Result := TCustomForm(ARoot).GetFormImage;
  end
  else if (ARoot is TWinControl) and TWinControl(ARoot).HandleAllocated then
  begin
    Result := TBitmap.Create;
    try
      Result.SetSize(TWinControl(ARoot).Width, TWinControl(ARoot).Height);
      TWinControl(ARoot).PaintTo(Result.Canvas.Handle, 0, 0);
    except
      FreeAndNil(Result);
      raise;
    end;
  end;
end;

/// <summary>Wurzel des ersten Formular-Editors im Modul; nil ohne.</summary>
function DesignerRoot(const AModule: IOTAModule): TComponent;
var
  mEditor: IOTAFormEditor;
  mComponent: INTAComponent;
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    if Supports(AModule.ModuleFileEditors[mIndex], IOTAFormEditor, mEditor) and
      Supports(mEditor.GetRootComponent, INTAComponent, mComponent) then
    begin
      Exit(mComponent.GetComponent);
    end;
  end;
end;

/// <summary>Bericht des Debuggers (#1455); nil, solange kein Modul eine Debug-Sitzung kennt.</summary>
function DebugReport: IAtlasDebugReportSource;
var
  mItem: IInterface;
begin
  Result := nil;
  if AtlasModuleRegistry = nil then
  begin
    Exit;
  end;
  for mItem in AtlasModuleRegistry.FindAll(IAtlasDebugReportSource) do
  begin
    if Supports(mItem, IAtlasDebugReportSource, Result) then
    begin
      Exit;
    end;
  end;
end;

{ TAtlasIdeAttachSources }

class function TAtlasIdeAttachSources.DesignerImage(out AName: string): TBitmap;
var
  mServices: IOTAModuleServices;
  mRoot: TComponent;
begin
  Result := nil;
  AName := '';
  mRoot := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) and (mServices.CurrentModule <> nil) then
  begin
    mRoot := DesignerRoot(mServices.CurrentModule);
  end;
  if mRoot <> nil then
  begin
    Result := RootImage(mRoot);
  end;
  if Result <> nil then
  begin
    AName := mRoot.Name;
  end;
end;

class function TAtlasIdeAttachSources.ProcessId: Cardinal;
var
  mReport: IAtlasDebugReportSource;
begin
  Result := 0;
  mReport := DebugReport;
  if mReport <> nil then
  begin
    Result := mReport.DebuggedProcessId;
  end;
end;

class function TAtlasIdeAttachSources.LaunchProject: string;
var
  mReport: IAtlasDebugReportSource;
begin
  Result := '';
  mReport := DebugReport;
  if mReport <> nil then
  begin
    Result := mReport.LaunchProject;
  end;
end;

class function TAtlasIdeAttachSources.DebugNote(out AMarkdown, AFileName: string): Boolean;
var
  mReport: IAtlasDebugReportSource;
begin
  AMarkdown := '';
  AFileName := '';
  mReport := DebugReport;
  Result := (mReport <> nil) and mReport.DebugNote(AMarkdown, AFileName);
end;

class function TAtlasIdeAttachSources.ExceptionsText(out ACount: Integer): string;
var
  mReport: IAtlasDebugReportSource;
begin
  Result := '';
  ACount := 0;
  mReport := DebugReport;
  if mReport <> nil then
  begin
    Result := mReport.ExceptionsText(cMaxExceptions, ACount);
  end;
end;

end.
