unit Atlas.Tests.SlashHost;

// Testhilfe für Schnellbefehle: ein Editor-Host ohne Projekt und Dateien, der
// Hinweise (Notify) und Cursorziele (MoveCursor) mitschreibt.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Editing.SlashCommands;

type
  TRecordingSlashHost = class(TInterfacedObject, ISlashHost)
  public
    Notes: TArray<string>;
    CursorUri: string;
    Cursor: TTextPosition;
    HasCursor: Boolean;
    function Project(const AUri: string; out AProject: TProjectInfo): Boolean;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function DirectoryExists(const APath: string): Boolean;
    procedure WriteProject(const AUri, AText: string);
    procedure SelectBuild(const AUri, AConfig, APlatform: string);
    procedure ShowDocument(const AFileName: string; const ASelection: TTextRange);
    function HeaderTemplate(const AUri: string): string;
    procedure WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
    function Setting(const AUri, AName: string): string;
    function TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
    procedure Notify(const AUri, AMessage: string);
    procedure MoveCursor(const AUri: string; const APosition: TTextPosition);
  end;

implementation

function TRecordingSlashHost.Project(const AUri: string; out AProject: TProjectInfo): Boolean;
begin
  AProject := Default(TProjectInfo);
  Result := False;
end;

function TRecordingSlashHost.ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function TRecordingSlashHost.DirectoryExists(const APath: string): Boolean;
begin
  Result := False;
end;

procedure TRecordingSlashHost.WriteProject(const AUri, AText: string);
begin
end;

procedure TRecordingSlashHost.SelectBuild(const AUri, AConfig, APlatform: string);
begin
end;

procedure TRecordingSlashHost.ShowDocument(const AFileName: string; const ASelection: TTextRange);
begin
end;

function TRecordingSlashHost.HeaderTemplate(const AUri: string): string;
begin
  Result := '';
end;

procedure TRecordingSlashHost.WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
begin
end;

function TRecordingSlashHost.Setting(const AUri, AName: string): string;
begin
  Result := '';
end;

function TRecordingSlashHost.TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
begin
  ATarget := Default(TSlashTestUnit);
  ATarget.Reason := 'Keine Testunits im Test';
  Result := False;
end;

procedure TRecordingSlashHost.Notify(const AUri, AMessage: string);
begin
  Notes := Notes + [AMessage];
end;

procedure TRecordingSlashHost.MoveCursor(const AUri: string; const APosition: TTextPosition);
begin
  CursorUri := AUri;
  Cursor := APosition;
  HasCursor := True;
end;

end.
