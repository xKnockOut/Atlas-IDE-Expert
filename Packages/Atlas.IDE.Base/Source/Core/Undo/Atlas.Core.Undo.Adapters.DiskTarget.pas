unit Atlas.Core.Undo.Adapters.DiskTarget;

// Ziel des Änderungsprotokolls (#721) für Dateien auf der Platte: Lesen und
// Schreiben in der Kodierung der Datei (TAtlasTextFile, Vorgabe "encoding"
// aus atlas.json, #121), binäre Formulare nie. Projekt und Papierkorb kennt
// der Kern nicht; die IDE-Schicht hängt sie über OnAddToProject,
// OnRemoveFromProject und OnRecycle ein. Ohne OnRecycle wird gelöscht.

interface

uses
  System.SysUtils,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Undo.Contract;

type
  TAtlasUndoFileProc = Atlas.Core.Undo.Contract.TAtlasUndoFileProc;

  TAtlasUndoDiskTarget = class(TInterfacedObject, IAtlasUndoTarget)
  private
    FOnAddToProject: TAtlasUndoFileProc;
    FOnRemoveFromProject: TAtlasUndoFileProc;
    FOnRecycle: TProc<string>;
  public
    function Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
    procedure Write(const AFileName: string; const AContent: TAtlasTextFileContent);
    procedure CreateFile(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
    procedure RemoveFile(const AFileName, AProject: string; AMode: TAtlasNewFilesMode);
    property OnAddToProject: TAtlasUndoFileProc read FOnAddToProject write FOnAddToProject;
    property OnRemoveFromProject: TAtlasUndoFileProc read FOnRemoveFromProject write FOnRemoveFromProject;
    /// <summary>Datei in den Papierkorb verschieben; nil = löschen.</summary>
    property OnRecycle: TProc<string> read FOnRecycle write FOnRecycle;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Files.EncodingDefault;

function TAtlasUndoDiskTarget.Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
begin
  AContent := Default(TAtlasTextFileContent);
  Result := TFile.Exists(AFileName);
  if Result then
  begin
    AContent := TAtlasTextFile.Load(AFileName, TAtlasEncodingDefault.CodePageFor(AFileName));
  end;
end;

procedure TAtlasUndoDiskTarget.Write(const AFileName: string; const AContent: TAtlasTextFileContent);
begin
  TAtlasTextFile.Save(AFileName, AContent);
end;

procedure TAtlasUndoDiskTarget.CreateFile(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
begin
  TDirectory.CreateDirectory(ExtractFilePath(AFileName));
  TAtlasTextFile.Save(AFileName, AContent);
  if (AProject <> '') and Assigned(FOnAddToProject) then
  begin
    FOnAddToProject(AFileName, AProject);
  end;
end;

procedure TAtlasUndoDiskTarget.RemoveFile(const AFileName, AProject: string; AMode: TAtlasNewFilesMode);
begin
  if (AProject <> '') and Assigned(FOnRemoveFromProject) then
  begin
    FOnRemoveFromProject(AFileName, AProject);
  end;
  if not TFile.Exists(AFileName) then
  begin
    Exit;
  end;
  case AMode of
    TAtlasNewFilesMode.RecycleBin:
      if Assigned(FOnRecycle) then
      begin
        FOnRecycle(AFileName);
      end
      else
      begin
        TFile.Delete(AFileName);
      end;
    TAtlasNewFilesMode.Delete:
      TFile.Delete(AFileName);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

end.
