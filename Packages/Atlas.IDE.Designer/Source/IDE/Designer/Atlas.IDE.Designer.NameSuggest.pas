unit Atlas.IDE.Designer.NameSuggest;

// Knopf „Sprechende Namen“ der Designer-Leiste (#608) in der IDE: sammelt die
// Komponenten des aktiven Formulars mit Standardnamen (Button1, Edit3),
// schlägt mit TAtlasNameSuggest Namen vor und benennt die im Dialog
// markierten um.
// - Eingaben: Caption bzw. Text, Label (FocusControl oder Lage im selben
//   Parent, in Pixeln der DFM), Namen der zugewiesenen Handler, DataField.
// - Umbenennen über den Designer: Name setzen benennt das Feld in der Unit um,
//   IDesigner.RenameMethod die Handler mit Standardnamen (Button1Click →
//   btnSpeichernClick, nach designer.nameSuggestRenameHandlers). Übrige
//   Verwendungen der alten Namen in der Unit des Formulars (ohne Zeichenketten
//   und Kommentare) ändert danach eine Atlas-Änderung
//   (TAtlasIdeWorkspaceEdit, ein Rückgängig-Schritt im Änderungsprotokoll).
// - „Letzte Umbenennung rückgängig“ benennt die Komponenten des letzten Laufs
//   im selben Formular zurück, ebenso ihre Handler und Verwendungen.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar;

type
  TAtlasNamePair = record
    OldName: string;
    NewName: string;
  end;

  TAtlasIdeNameSuggest = class
  public const
    cId = 'nameSuggest';
  private
    FOnMessage: TProc<string>;
    FLastForm: string;
    FLast: TArray<TAtlasNamePair>;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    /// <summary>Knopf nach den Einstellungen; Id leer, wenn ausgeschaltet.</summary>
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick: Dialog für das Formular im aktiven Designer.</summary>
    procedure Run;
  end;

implementation

uses
  System.Classes,
  System.Types,
  System.TypInfo,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Designer.NameSuggest,
  Atlas.UI.Designer.NameDialog,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.Model,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.Settings;

const
  cUmlautRemove = 'remove';

type
  TEventRef = record
    Component: TComponent;
    Info: PPropInfo;
  end;

/// <summary>Belegte Ereignisse von AComponent mit dem Namen ihres Handlers.</summary>
function HandlersOf(AComponent: TComponent; const ADesigner: IDesigner; out AEvents: TArray<TEventRef>):
  TArray<string>;
var
  mList: PPropList;
  mCount, mIndex: Integer;
  mMethod: TMethod;
  mEvent: TEventRef;
begin
  Result := nil;
  AEvents := nil;
  mCount := GetPropList(AComponent, mList);
  try
    for mIndex := 0 to mCount - 1 do
    begin
      if mList^[mIndex]^.PropType^.Kind <> tkMethod then
      begin
        Continue;
      end;
      mMethod := GetMethodProp(AComponent, mList^[mIndex]);
      if mMethod.Code = nil then
      begin
        Continue;
      end;
      mEvent.Component := AComponent;
      mEvent.Info := mList^[mIndex];
      AEvents := AEvents + [mEvent];
      Result := Result + [ADesigner.GetMethodName(mMethod)];
    end;
  finally
    FreeMem(mList);
  end;
end;

function LabelsOf(ARoot: TComponent; const AScale: TAtlasDesignScale): TArray<TAtlasNameLabel>;
var
  mIndex: Integer;
  mComponent: TComponent;
  mLabel: TAtlasNameLabel;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    mLabel := Default(TAtlasNameLabel);
    if not (mComponent is TCustomLabel) or not TAtlasDesignerAccess.PropText(mComponent, 'Caption',
      mLabel.Caption) then
    begin
      Continue;
    end;
    mLabel.Bounds := AScale.ToDesign(TControl(mComponent).BoundsRect);
    mLabel.ParentName := TAtlasDesignerAccess.ParentNameOf(TControl(mComponent), ARoot);
    TAtlasDesignerAccess.PropText(mComponent, 'FocusControl', mLabel.FocusControl);
    Result := Result + [mLabel];
  end;
end;

function InputOf(AComponent, ARoot: TComponent; const ADesigner: IDesigner; const ALabels: TArray<TAtlasNameLabel>;
  const AScale: TAtlasDesignScale): TAtlasNameInput;
var
  mEvents: TArray<TEventRef>;
begin
  Result := Default(TAtlasNameInput);
  Result.Name := AComponent.Name;
  Result.ClassChain := TAtlasDesignerAccess.ClassChain(AComponent);
  if not TAtlasDesignerAccess.PropText(AComponent, 'Caption', Result.Caption) then
  begin
    TAtlasDesignerAccess.PropText(AComponent, 'Text', Result.Caption);
  end;
  if AComponent is TControl then
  begin
    Result.LabelText := TAtlasNameSuggest.LabelFor(AComponent.Name,
      TAtlasDesignerAccess.ParentNameOf(TControl(AComponent), ARoot), AScale.ToDesign(TControl(AComponent).BoundsRect),
      ALabels);
  end;
  Result.Handlers := HandlersOf(AComponent, ADesigner, mEvents);
  TAtlasDesignerAccess.PropText(AComponent, 'DataField', Result.DataField);
end;

function SourceText(ASource: TAtlasNameSource): string;
begin
  case ASource of
    TAtlasNameSource.Caption:
      Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameSourceCaption);
    TAtlasNameSource.LabelText:
      Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameSourceLabel);
    TAtlasNameSource.Handler:
      Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameSourceHandler);
    TAtlasNameSource.DataField:
      Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameSourceDataField);
  else
    Result := '';
  end;
end;

function OptionsOf(const ASettings: TAtlasPluginSettings): TAtlasNameOptions;
begin
  Result := Default(TAtlasNameOptions);
  Result.Sources := TAtlasNameSuggest.ParseSources(ASettings.DesignerNameSuggestSources);
  Result.Umlauts := TAtlasUmlautRule.Replace;
  if SameText(ASettings.DesignerNameSuggestUmlauts, cUmlautRemove) then
  begin
    Result.Umlauts := TAtlasUmlautRule.Remove;
  end;
  Result.Prefixes := ASettings.DesignerNameSuggestPrefixes;
end;

/// <summary>Zeilen für den Dialog: Komponenten mit Standardnamen und ihre Vorschläge.</summary>
function RowsOf(ARoot: TComponent; const ADesigner: IDesigner): TArray<TAtlasNameRow>;
var
  mScale: TAtlasDesignScale;
  mLabels: TArray<TAtlasNameLabel>;
  mInputs: TArray<TAtlasNameInput>;
  mTaken: TArray<string>;
  mProposals: TArray<TAtlasNameProposal>;
  mIndex: Integer;
  mComponent: TComponent;
  mRow: TAtlasNameRow;
begin
  Result := nil;
  mScale := TAtlasDesignScale.ForRoot(TWinControl(ARoot));
  mLabels := LabelsOf(ARoot, mScale);
  mInputs := nil;
  mTaken := [ARoot.Name];
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    mTaken := mTaken + [mComponent.Name];
    if (mComponent.Name <> '') and TAtlasNameSuggest.IsDefaultName(mComponent.Name, mComponent.ClassName) then
    begin
      mInputs := mInputs + [InputOf(mComponent, ARoot, ADesigner, mLabels, mScale)];
    end;
  end;
  mProposals := TAtlasNameSuggest.Propose(mInputs, OptionsOf(TAtlasIdeSettings.Current), mTaken);
  for mIndex := 0 to High(mProposals) do
  begin
    mRow := Default(TAtlasNameRow);
    mRow.OldName := mProposals[mIndex].OldName;
    mRow.ClassName := mInputs[mIndex].ClassChain[0];
    mRow.SourceText := SourceText(mProposals[mIndex].Source);
    mRow.NewName := mProposals[mIndex].NewName;
    mRow.Checked := mRow.NewName <> '';
    if mRow.NewName = '' then
    begin
      mRow.Note := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameNoSource);
    end
    else if mProposals[mIndex].Collision then
    begin
      mRow.Note := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameCollision);
    end;
    Result := Result + [mRow];
  end;
end;

type
  TRenameCount = record
    Components: Integer;
    Handlers: Integer;
    Places: Integer;
  end;

/// <summary>Benennt die Handler mit Standardnamen von AComponent mit; ergänzt APairs.</summary>
function RenameHandlers(AComponent: TComponent; const ADesigner: IDesigner; const APair: TAtlasNamePair;
  var APairs: TArray<TAtlasNamePair>): Integer;
var
  mEvents: TArray<TEventRef>;
  mHandler: string;
  mPair: TAtlasNamePair;
begin
  Result := 0;
  for mHandler in HandlersOf(AComponent, ADesigner, mEvents) do
  begin
    mPair.OldName := mHandler;
    mPair.NewName := TAtlasNameSuggest.HandlerName(mHandler, APair.OldName, APair.NewName);
    if (mPair.NewName = '') or ADesigner.MethodExists(mPair.NewName) or not ADesigner.MethodExists(mHandler) then
    begin
      Continue;
    end;
    ADesigner.RenameMethod(mPair.OldName, mPair.NewName);
    APairs := APairs + [mPair];
    Inc(Result);
  end;
end;

/// <summary>Übrige Verwendungen der alten Namen in der Unit des Formulars.</summary>
function RenameInCode(const AEditor: IOTAFormEditor; const APairs: TArray<TAtlasNamePair>;
  const AOnMessage: TProc<string>): Integer;
var
  mFile: TLspFileEdits;
  mText: string;
  mPair: TAtlasNamePair;
  mPlace: TAtlasNamePlace;
  mEdit: TLspTextEdit;
  mWorkspace: TLspWorkspaceEdit;
  mResult: TAtlasWorkspaceEditResult;
begin
  Result := 0;
  mFile := Default(TLspFileEdits);
  mFile.FileName := ChangeFileExt(AEditor.FileName, '.pas');
  mText := TAtlasIdeWorkspaceEdit.CurrentText(mFile.FileName);
  for mPair in APairs do
  begin
    for mPlace in TAtlasNameSuggest.Places(mText, mPair.OldName) do
    begin
      mEdit := Default(TLspTextEdit);
      mEdit.StartPos := TLspTextPosition.Create(mPlace.Line, mPlace.Character);
      mEdit.EndPos := TLspTextPosition.Create(mPlace.Line, mPlace.Character + Length(mPair.OldName));
      mEdit.NewText := mPair.NewName;
      mFile.Edits := mFile.Edits + [mEdit];
    end;
  end;
  if Length(mFile.Edits) = 0 then
  begin
    Exit;
  end;
  mWorkspace := Default(TLspWorkspaceEdit);
  mWorkspace.Files := [mFile];
  mResult := TAtlasIdeWorkspaceEdit.Apply(mWorkspace, TAtlasUnopenedPolicy.OpenInEditor,
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameAction));
  if mResult.Error <> '' then
  begin
    AOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.NameCodeFailed, [mResult.Error]));
    Exit;
  end;
  Result := Length(mFile.Edits);
end;

/// <summary>Benennt die Komponenten aus APairs um (Designer, Handler, Code); liefert die gelungenen Paare.</summary>
function RenameAll(const AEditor: IOTAFormEditor; ARoot: TComponent; const APairs: TArray<TAtlasNamePair>;
  const AOnMessage: TProc<string>; out ACount: TRenameCount): TArray<TAtlasNamePair>;
var
  mDesigner: IDesigner;
  mPair: TAtlasNamePair;
  mComponent: TComponent;
  mCode: TArray<TAtlasNamePair>;
begin
  Result := nil;
  ACount := Default(TRenameCount);
  mCode := nil;
  mDesigner := TAtlasDesignerAccess.DesignerOf(AEditor);
  for mPair in APairs do
  begin
    mComponent := ARoot.FindComponent(mPair.OldName);
    if mComponent = nil then
    begin
      Continue;
    end;
    try
      // Der Designer benennt dabei das Feld in der Unit um.
      mComponent.Name := mPair.NewName;
    except
      on E: EComponentError do
      begin
        AOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.NameFailed, [mPair.OldName, E.Message]));
        Continue;
      end;
    end;
    Result := Result + [mPair];
    mCode := mCode + [mPair];
    Inc(ACount.Components);
    if TAtlasIdeSettings.Current.DesignerNameSuggestRenameHandlers then
    begin
      Inc(ACount.Handlers, RenameHandlers(mComponent, mDesigner, mPair, mCode));
    end;
  end;
  if ACount.Components > 0 then
  begin
    mDesigner.Modified;
    ACount.Places := RenameInCode(AEditor, mCode, AOnMessage);
  end;
end;

function Reversed(const APairs: TArray<TAtlasNamePair>): TArray<TAtlasNamePair>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(APairs));
  for mIndex := 0 to High(APairs) do
  begin
    Result[mIndex].OldName := APairs[mIndex].NewName;
    Result[mIndex].NewName := APairs[mIndex].OldName;
  end;
end;

{ TAtlasIdeNameSuggest }

constructor TAtlasIdeNameSuggest.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

function TAtlasIdeNameSuggest.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
begin
  if not ASettings.DesignerNameSuggest then
  begin
    Exit(Default(TAtlasDesignerButton));
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.NameSuggest,
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameHint));
end;

procedure TAtlasIdeNameSuggest.Run;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mRows: TArray<TAtlasNameRow>;
  mRow: TAtlasNameRow;
  mPairs, mDone: TArray<TAtlasNamePair>;
  mPair: TAtlasNamePair;
  mCanUndo: Boolean;
  mCount: TRenameCount;
  mDesigner: IDesigner;
begin
  mDesigner := nil;
  if TAtlasDesignerAccess.Current(mEditor, mRoot) and (mRoot is TWinControl) then
  begin
    mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  end;
  if mDesigner = nil then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ToolNoForm));
    Exit;
  end;
  mRows := RowsOf(mRoot, mDesigner);
  mCanUndo := (Length(FLast) > 0) and SameText(FLastForm, mRoot.Name);
  if (Length(mRows) = 0) and not mCanUndo then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.NameNone, [mRoot.Name]));
    Exit;
  end;
  case TAtlasNameDialog.Execute(mRoot.Name, mRows, mCanUndo,
    procedure(AForm: TForm)
    begin
      TAtlasIdeDockWindow.ApplyIdeTheme(AForm);
    end) of
    TAtlasNameDialogResult.Apply:
      begin
        mPairs := nil;
        for mRow in mRows do
        begin
          if mRow.Checked and IsValidIdent(mRow.NewName) and not SameText(mRow.NewName, mRow.OldName) then
          begin
            mPair.OldName := mRow.OldName;
            mPair.NewName := mRow.NewName;
            mPairs := mPairs + [mPair];
          end;
        end;
        mDone := RenameAll(mEditor, mRoot, mPairs, FOnMessage, mCount);
        if Length(mDone) > 0 then
        begin
          FLast := mDone;
          FLastForm := mRoot.Name;
        end;
        FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.NameDone, [mCount.Components,
          mCount.Handlers, mCount.Places]));
      end;
    TAtlasNameDialogResult.Undo:
      begin
        RenameAll(mEditor, mRoot, Reversed(FLast), FOnMessage, mCount);
        FLast := nil;
        FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.NameUndone, [mCount.Components]));
      end;
  end;
end;

end.
