unit Atlas.IDE.Problems.Adapters.Editors;

// Die IDE für den Ablauf der Probleme (IAtlasProblemsEditors, #398): oberer
// Editor mit gemeinsamem Pufferstand (TAtlasEditorSnapshots), geöffnete
// Module, Text angeforderter Dateien aus Puffer oder Platte (#1817),
// Debugger (#1241) und Fehler der IDE über das Modul Prüfregeln (#1819).
// Nur die Kompositionswurzel legt den Adapter an
// (Atlas.IDE.CodeInsight.Composition.IdeAdapters). Nur im Hauptthread.

interface

uses
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Contract.Sync;

type
  TAtlasIdeProblemsEditors = class(TInterfacedObject, IAtlasProblemsEditors)
  public
    function ActiveEditor(out AEditor: TAtlasProblemsEditor): Boolean;
    function IsOpen(const AFileName: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function Debugging: Boolean;
    function IdeErrorsEnabled: Boolean;
    function IdeErrors(const AFileName: string; out AErrors: TArray<TAtlasProblem>): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Files.TextFile,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.CodeView,
  Atlas.IDE.Problems.IdeErrors,
  Atlas.IDE.Problems.Controller;

{ TAtlasIdeProblemsEditors }

function TAtlasIdeProblemsEditors.ActiveEditor(out AEditor: TAtlasProblemsEditor): Boolean;
var
  mView: IOTAEditView;
  mSnapshot: TAtlasEditorSnapshot;
begin
  AEditor := Default(TAtlasProblemsEditor);
  // Ohne Fokus weder Puffer lesen noch abgleichen.
  mView := nil;
  if Application.Active then
  begin
    mView := TAtlasEditorBuffer.TopSourceView;
  end;
  Result := mView <> nil;
  if not Result then
  begin
    Exit;
  end;
  // Gemeinsamer Pufferstand: gelesen nur nach einer Änderung.
  mSnapshot := TAtlasEditorSnapshots.Get(mView);
  AEditor.FileName := mView.Buffer.FileName;
  AEditor.Text := mSnapshot.Text;
  AEditor.Version := mSnapshot.Version;
  AEditor.Modified := mView.Buffer.IsModified;
  AEditor.CodeInFront := TAtlasIdeCodeView.InFront;
end;

function TAtlasIdeProblemsEditors.IsOpen(const AFileName: string): Boolean;
var
  mModules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.FindModule(AFileName) <> nil);
end;

function TAtlasIdeProblemsEditors.ReadText(const AFileName: string; out AText: string): Boolean;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mBuffer: IOTAEditBuffer;
  mIndex: Integer;
begin
  AText := '';
  mModule := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mModule := mModules.FindModule(AFileName);
  end;
  if mModule <> nil then
  begin
    for mIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if Supports(mModule.ModuleFileEditors[mIndex], IOTAEditBuffer, mBuffer) and
        SameText(mBuffer.FileName, AFileName) then
      begin
        AText := TAtlasEditorBuffer.Text(mBuffer);
        Exit(True);
      end;
    end;
  end;
  try
    AText := TAtlasTextFile.LoadText(AFileName);
    Result := True;
  except
    // Fehlt oder gesperrt: Die Datei bleibt ungeprüft, die übrigen nicht.
    on EStreamError do
      Result := False;
  end;
end;

function TAtlasIdeProblemsEditors.Debugging: Boolean;
begin
  Result := TAtlasProblemsController.Paused;
end;

function TAtlasIdeProblemsEditors.IdeErrorsEnabled: Boolean;
begin
  Result := TAtlasIdeErrorSource.Enabled;
end;

function TAtlasIdeProblemsEditors.IdeErrors(const AFileName: string; out AErrors: TArray<TAtlasProblem>): Boolean;
begin
  Result := TAtlasIdeErrorSource.Query(AFileName, AErrors);
end;

end.
