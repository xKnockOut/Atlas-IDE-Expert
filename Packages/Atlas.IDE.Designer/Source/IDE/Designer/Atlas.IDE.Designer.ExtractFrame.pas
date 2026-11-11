unit Atlas.IDE.Designer.ExtractFrame;

// Knopf „In Frame auslagern“ der Designer-Leiste (#611) in der IDE: nimmt
// die Auswahl im aktiven Formular, zeigt den Dialog mit Vorschau je Datei
// (TAtlasExtractFrame auf dem aktuellen Text von Unit und DFM) und setzt die
// Änderung als Textänderung mit Neuladen um, nicht über zwei offene
// Designer:
// - schließt das Formular ohne Rückfrage (sein Stand steckt in den Texten),
//   schreibt Frame-Unit und -DFM, Formular-Unit und -DFM in der Kodierung der
//   Dateien, trägt die Frame-Unit ins Projekt ein, öffnet den Frame und
//   danach das Formular wieder.
// - „Letzte Auslagerung rückgängig“ schließt beide, trägt die Frame-Unit aus,
//   schreibt die alten Texte des Formulars zurück, verschiebt die Frame-Dateien
//   in den Papierkorb und öffnet das Formular wieder.
// Schließen und Öffnen laufen nach dem Klick (TAtlasMainThread.ForceQueue), damit der Designer
// mit der Leiste nicht unter dem Klick verschwindet. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar;

type
  TAtlasIdeExtractFrame = class
  public const
    cId = 'extractFrame';
  private type
    TUndoState = record
      FormFile: string;
      FormDfm: string;
      OldUnit: string;
      OldDfm: string;
      FrameFile: string;
      Project: string;
    end;
  private
    FOnMessage: TProc<string>;
    FLast: TUndoState;
    procedure Undo;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    /// <summary>Knopf nach den Einstellungen; Id leer, wenn ausgeschaltet.</summary>
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick: Dialog für die Auswahl im aktiven Designer.</summary>
    procedure Run;
  end;

implementation

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Designer.ExtractFrame,
  Atlas.UI.Designer.ExtractDialog,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Undo.Target;

type
  /// <summary>Was ein Lauf braucht: Formular, Auswahl und die Texte vor dem Auslagern.</summary>
  TExtractSource = record
    FormFile: string;
    FormDfm: string;
    FormClass: string;
    OldUnit: string;
    OldDfm: string;
    Names: TArray<string>;
    Taken: TArray<string>;
    Project: string;
  end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function PartsOf(const AText: string; out AArg: string): string;
var
  mBar: Integer;
begin
  mBar := Pos('|', AText);
  if mBar = 0 then
  begin
    AArg := '';
    Exit(AText);
  end;
  Result := Copy(AText, 1, mBar - 1);
  AArg := Copy(AText, mBar + 1, MaxInt);
end;

function ErrorText(const AError: string): string;
var
  mKind, mArg: string;
begin
  mKind := PartsOf(AError, mArg);
  if mKind = TAtlasExtractNote.cErrParents then
  begin
    Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfErrParents);
  end
  else if mKind = TAtlasExtractNote.cErrNotFound then
  begin
    Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfErrNotFound, [mArg]);
  end
  else if mKind = TAtlasExtractNote.cErrClass then
  begin
    Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfErrClass);
  end
  else if mKind = TAtlasExtractNote.cErrName then
  begin
    Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfErrName);
  end
  else
  begin
    Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfErrNothing);
  end;
end;

function NoteText(const ANote: string): string;
var
  mKind, mArg: string;
begin
  mKind := PartsOf(ANote, mArg);
  if mKind = TAtlasExtractNote.cKept then
  begin
    Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfNoteKept, [mArg]);
  end
  else if mKind = TAtlasExtractNote.cFormField then
  begin
    Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfNoteFormField, [mArg]);
  end
  else
  begin
    Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfNoteContainer, [mArg]);
  end;
end;

function OptionsOf(const ASource: TExtractSource; const AInput: TAtlasExtractInput): TAtlasExtractOptions;
begin
  Result := Default(TAtlasExtractOptions);
  Result.Names := ASource.Names;
  Result.FrameClass := AInput.FrameClass;
  Result.FrameUnit := AInput.FrameUnit;
  Result.InstanceName := AInput.InstanceName;
  Result.MoveHandlers := AInput.MoveHandlers;
  Result.ContainerAsFrame := AInput.ContainerAsFrame;
end;

function FrameFileOf(const AInput: TAtlasExtractInput): string;
begin
  Result := IncludeTrailingPathDelimiter(AInput.Folder) + AInput.FrameUnit + '.pas';
end;

/// <summary>Prüfungen, die Dateien und Formular brauchen; '' wenn alles passt.</summary>
function CheckTarget(const ASource: TExtractSource; const AInput: TAtlasExtractInput;
  const AResult: TAtlasExtractResult): string;
var
  mFile: string;
begin
  Result := '';
  mFile := FrameFileOf(AInput);
  if not DirectoryExists(AInput.Folder) then
  begin
    Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfErrFolder, [AInput.Folder]);
  end
  else if FileExists(mFile) or FileExists(ChangeFileExt(mFile, '.dfm')) then
  begin
    Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfErrExists, [ExtractFileName(mFile)]);
  end
  else if Contains(ASource.Taken, AInput.InstanceName) and not Contains(AResult.Moved, AInput.InstanceName) and
    not Contains(ASource.Names, AInput.InstanceName) then
  begin
    Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfErrTaken, [AInput.InstanceName]);
  end;
end;

function PreviewOf(const ASource: TExtractSource; const AInput: TAtlasExtractInput;
  out AResult: TAtlasExtractResult): TAtlasExtractPreview;
var
  mNote, mFrame: string;
begin
  Result := Default(TAtlasExtractPreview);
  AResult := TAtlasExtractFrame.Run(ASource.OldDfm, ASource.OldUnit, ASource.FormClass, OptionsOf(ASource, AInput));
  if AResult.Error <> '' then
  begin
    Result.Error := ErrorText(AResult.Error);
    Exit;
  end;
  Result.Error := CheckTarget(ASource, AInput, AResult);
  mFrame := FrameFileOf(AInput);
  Result.Captions := [ExtractFileName(mFrame), ExtractFileName(ChangeFileExt(mFrame, '.dfm')),
    ExtractFileName(ASource.FormFile), ExtractFileName(ASource.FormDfm)];
  Result.Texts := [AResult.FrameUnit, AResult.FrameDfm, AResult.FormUnit, AResult.FormDfm];
  for mNote in AResult.Notes do
  begin
    Result.Notes := Result.Notes + [NoteText(mNote)];
  end;
  if ASource.Project <> '' then
  begin
    Result.Notes := Result.Notes + [TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfNoteProject,
      [AInput.FrameUnit, ExtractFileName(ASource.Project)])];
  end;
end;

function ProjectOf(const AFileName: string): IOTAProject;
begin
  Result := nil;
  if AFileName <> '' then
  begin
    Supports(TAtlasIdeFiles.ProjectModule(AFileName), IOTAProject, Result);
  end;
end;

procedure CloseModule(const AFileName: string);
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
begin
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    mModule := mServices.FindModule(AFileName);
    // Der Stand steckt in den geschriebenen Texten; ohne Rückfrage schließen.
    if mModule <> nil then
    begin
      mModule.CloseModule(True);
    end;
  end;
end;

procedure OpenForm(const AFileName: string);
var
  mActions: IOTAActionServices;
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
begin
  if not Supports(BorlandIDEServices, IOTAActionServices, mActions) or not mActions.OpenFile(AFileName) then
  begin
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    mModule := mServices.FindModule(AFileName);
    if mModule <> nil then
    begin
      mModule.ShowFilename(ChangeFileExt(AFileName, '.dfm'));
    end;
  end;
end;

/// <summary>Schreibt AText in der Kodierung der vorhandenen Datei (neu: UTF-8 mit BOM).</summary>
procedure SaveText(const AFileName, AText: string);
var
  mContent: TAtlasTextFileContent;
begin
  mContent := TAtlasIdeFiles.DiskEncoding(AFileName);
  mContent.Text := AText;
  TAtlasTextFile.Save(AFileName, mContent);
end;

{ TAtlasIdeExtractFrame }

constructor TAtlasIdeExtractFrame.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

function TAtlasIdeExtractFrame.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
begin
  if not ASettings.DesignerExtractFrame then
  begin
    Exit(Default(TAtlasDesignerButton));
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.ExtractFrame,
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfHint));
end;

function SourceOf(const AEditor: IOTAFormEditor; ARoot: TComponent; out ASource: TExtractSource): Boolean;
var
  mComponent: TComponent;
  mIndex: Integer;
begin
  ASource := Default(TExtractSource);
  ASource.FormFile := ChangeFileExt(AEditor.FileName, '.pas');
  ASource.FormDfm := ChangeFileExt(AEditor.FileName, '.dfm');
  // Im Designer trägt das Formular den Namen seiner Klasse (TfrmKunden).
  ASource.FormClass := ARoot.ClassName;
  ASource.OldUnit := TAtlasIdeWorkspaceEdit.CurrentText(ASource.FormFile);
  ASource.OldDfm := TAtlasIdeWorkspaceEdit.CurrentText(ASource.FormDfm);
  ASource.Project := TAtlasIdeFiles.ProjectOfFile(ASource.FormFile);
  for mComponent in TAtlasDesignerAccess.Selection(AEditor, ARoot) do
  begin
    ASource.Names := ASource.Names + [mComponent.Name];
  end;
  ASource.Taken := [ARoot.Name];
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    ASource.Taken := ASource.Taken + [ARoot.Components[mIndex].Name];
  end;
  Result := (ASource.OldUnit <> '') and (ASource.OldDfm <> '');
end;

function InputOf(const AEditor: IOTAFormEditor; ARoot: TComponent; const ASource: TExtractSource):
  TAtlasExtractInput;
var
  mSelection: TArray<TComponent>;
begin
  Result := Default(TAtlasExtractInput);
  Result.Folder := ExtractFilePath(ASource.FormFile);
  Result.MoveHandlers := True;
  mSelection := TAtlasDesignerAccess.Selection(AEditor, ARoot);
  Result.CanContainer := (Length(mSelection) = 1) and (mSelection[0] is TWinControl) and
    (TWinControl(mSelection[0]).ControlCount > 0);
  Result.ContainerAsFrame := Result.CanContainer;
  if Length(ASource.Names) > 0 then
  begin
    TAtlasExtractFrame.Suggest(ASource.Names[0], Result.FrameClass, Result.FrameUnit, Result.InstanceName);
  end;
end;

procedure TAtlasIdeExtractFrame.Run;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSource: TExtractSource;
  mInput: TAtlasExtractInput;
  mResult: TAtlasExtractResult;
  mPreview: TAtlasExtractPreview;
  mCanUndo: Boolean;
  mOnMessage: TProc<string>;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or not SourceOf(mEditor, mRoot, mSource) then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ToolNoForm));
    Exit;
  end;
  mCanUndo := SameText(FLast.FormFile, mSource.FormFile);
  if (Length(mSource.Names) = 0) and not mCanUndo then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfNoSelection));
    Exit;
  end;
  mInput := InputOf(mEditor, mRoot, mSource);
  case TAtlasExtractDialog.Execute(mRoot.Name, mInput, mCanUndo,
    function(AInput: TAtlasExtractInput): TAtlasExtractPreview
    var
      mIgnored: TAtlasExtractResult;
    begin
      Result := PreviewOf(mSource, AInput, mIgnored);
    end,
    procedure(AForm: TForm)
    begin
      TAtlasIdeDockWindow.ApplyIdeTheme(AForm);
    end) of
    TAtlasExtractDialogResult.Apply:
      begin
        mPreview := PreviewOf(mSource, mInput, mResult);
        if mPreview.Error <> '' then
        begin
          FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfFailed, [mPreview.Error]));
          Exit;
        end;
        FLast := Default(TUndoState);
        FLast.FormFile := mSource.FormFile;
        FLast.FormDfm := mSource.FormDfm;
        FLast.OldUnit := mSource.OldUnit;
        FLast.OldDfm := mSource.OldDfm;
        FLast.FrameFile := FrameFileOf(mInput);
        FLast.Project := mSource.Project;
        mOnMessage := FOnMessage;
        TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
          procedure
          var
            mProject: IOTAProject;
          begin
            try
              SaveText(FrameFileOf(mInput), mResult.FrameUnit);
              SaveText(ChangeFileExt(FrameFileOf(mInput), '.dfm'), mResult.FrameDfm);
              CloseModule(mSource.FormFile);
              SaveText(mSource.FormFile, mResult.FormUnit);
              SaveText(mSource.FormDfm, mResult.FormDfm);
            except
              on E: EAtlasTextFileError do
              begin
                mOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfFailed, [E.Message]));
                Exit;
              end;
            end;
            mProject := ProjectOf(mSource.Project);
            if mProject <> nil then
            begin
              mProject.AddFile(FrameFileOf(mInput), True);
            end;
            OpenForm(FrameFileOf(mInput));
            OpenForm(mSource.FormFile);
            mOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfDone, [mInput.FrameClass,
              mInput.FrameUnit, Length(mResult.Moved), Length(mResult.MovedHandlers)]));
          end);
      end;
    TAtlasExtractDialogResult.Undo:
      Undo;
  end;
end;

procedure TAtlasIdeExtractFrame.Undo;
var
  mLast: TUndoState;
  mOnMessage: TProc<string>;
begin
  mLast := FLast;
  FLast := Default(TUndoState);
  mOnMessage := FOnMessage;
  TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
    procedure
    var
      mProject: IOTAProject;
    begin
      CloseModule(mLast.FrameFile);
      CloseModule(mLast.FormFile);
      mProject := ProjectOf(mLast.Project);
      if mProject <> nil then
      begin
        mProject.RemoveFile(mLast.FrameFile);
      end;
      try
        SaveText(mLast.FormFile, mLast.OldUnit);
        SaveText(mLast.FormDfm, mLast.OldDfm);
        TAtlasIdeUndoTarget.Recycle(ChangeFileExt(mLast.FrameFile, '.dfm'));
        TAtlasIdeUndoTarget.Recycle(mLast.FrameFile);
      except
        on E: EAtlasTextFileError do
        begin
          mOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfFailed, [E.Message]));
        end;
        on E: EInOutError do
        begin
          mOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfFailed, [E.Message]));
        end;
      end;
      OpenForm(mLast.FormFile);
      mOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfUndone,
        [ExtractFileName(mLast.FormFile)]));
    end);
end;

end.
