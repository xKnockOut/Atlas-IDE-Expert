unit Atlas.IDE.Designer.DataBindings;

// Datenbindung der Auswahl als Brotkrumenleiste (#610,
// designer.dataBindings): Knopf in der Designer-Leiste, der eine Leiste
// (TAtlasBindingBar) am unteren Rand des Designers ein- und ausschaltet.
// - Leisten je Editorfenster über den Leisten-Host (ShowIn Designer, unten
//   ausgerichtet), wie die Designer-Leiste oben.
// - Daten: Komponenten des Formulars im Designer und aller im Projekt
//   geöffneten Formulare und Datenmodule. Verweise (Connection,
//   SQLConnection, DataSet, MasterSource, DataSource, ListSource) und Texte
//   (ProviderName, DataField, ListField, KeyField) liest Atlas über RTTI;
//   Ziele in einem anderen Modul heißen „dmDaten.dsKunden“. Persistente
//   Felder (Komponenten mit FieldName und einer Datenmenge als Elternobjekt)
//   hängen an ihrer Datenmenge. Daraus rechnet TAtlasDataBindings.Trail die
//   Glieder zur einzigen gewählten Komponente.
// - Ein Takt (400 ms) vergleicht eine Kennung aus Objekten, Verweisen und
//   Auswahl und zeichnet nur bei Änderung neu; er läuft nur, solange die
//   Leiste eingeschaltet ist.
// - Klick auf ein Glied wählt die Komponente im Designer; liegt sie in einem
//   anderen Modul, zeigt Atlas dessen Designer und wählt sie dort.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Designer.DataBindings,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.BindingBar,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Designer.PaletteImages;

type
  TAtlasIdeDataBindings = class
  public const
    cId = 'dataBindings';
  private
    FHost: TAtlasEditorBarHost;
    FTimer: TTimer;
    FPalette: TAtlasPaletteImages;
    FShown: Boolean;
    FKey: string;
    function CreateBar: TAtlasBindingBar;
    procedure Tick(Sender: TObject);
    procedure Refresh;
    function ObjectsOf(ARoot: TComponent): TArray<TAtlasBindingObject>;
    procedure Select(const AId: string);
    procedure Hide;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Knopf nach den Einstellungen; Id leer, wenn ausgeschaltet.</summary>
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick: Leiste ein- bzw. ausschalten.</summary>
    procedure Toggle;
    procedure ApplyTheme;
  end;

implementation

uses
  System.TypInfo,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Palette,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.DesignerView,
  Atlas.IDE.Foundation.EditorStyle;

const
  cTick = 400;
  cFieldName = 'FieldName';
  cKeySeparator = '#';

{ Hilfen }

/// <summary>Formular-Editoren aller im Projekt geöffneten Formulare und Datenmodule.</summary>
function OpenFormEditors: TArray<IOTAFormEditor>;
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
  mEditor: IOTAFormEditor;
  mIndex, mFile: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mModule := mServices.Modules[mIndex];
    for mFile := 0 to mModule.GetModuleFileCount - 1 do
    begin
      if Supports(mModule.GetModuleFileEditor(mFile), IOTAFormEditor, mEditor) then
      begin
        Result := Result + [mEditor];
      end;
    end;
  end;
end;

/// <summary>Wert der Eigenschaft AName: Text, bei einem Verweis der Name des Ziels (aus einem anderen Modul
/// „Modul.Name“); leer ohne sie.</summary>
function PropValue(AComponent: TComponent; const AName: string): string;
var
  mProp: PPropInfo;
  mTarget: TObject;
begin
  Result := '';
  mProp := GetPropInfo(AComponent, AName);
  if mProp = nil then
  begin
    Exit;
  end;
  case mProp^.PropType^.Kind of
    tkString, tkLString, tkWString, tkUString:
      Result := GetStrProp(AComponent, mProp);
    tkClass:
      begin
        mTarget := GetObjectProp(AComponent, mProp);
        if (mTarget is TComponent) and (TComponent(mTarget).Name <> '') then
        begin
          Result := TComponent(mTarget).Name;
          if (TComponent(mTarget).Owner <> nil) and (TComponent(mTarget).Owner <> AComponent.Owner) then
          begin
            Result := TComponent(mTarget).Owner.Name + '.' + Result;
          end;
        end;
      end;
  end;
end;

/// <summary>Persistentes Feld: Komponente mit FieldName, deren Elternobjekt eine Komponente ist.</summary>
function IsField(AComponent: TComponent; out ADataSet: TComponent; out AFieldName: string): Boolean;
begin
  ADataSet := nil;
  AFieldName := '';
  Result := AComponent.HasParent and (GetPropInfo(AComponent, cFieldName) <> nil);
  if Result then
  begin
    ADataSet := AComponent.GetParentComponent;
    AFieldName := PropValue(AComponent, cFieldName);
    Result := (ADataSet <> nil) and (AFieldName <> '');
  end;
end;

function ObjectOf(AComponent: TComponent; const AModule: string): TAtlasBindingObject;
begin
  Result := Default(TAtlasBindingObject);
  Result.Module := AModule;
  Result.Name := AComponent.Name;
  Result.ClassName := AComponent.ClassName;
  Result.Connection := PropValue(AComponent, 'Connection');
  Result.SQLConnection := PropValue(AComponent, 'SQLConnection');
  Result.DataSet := PropValue(AComponent, 'DataSet');
  Result.MasterSource := PropValue(AComponent, 'MasterSource');
  Result.DataSource := PropValue(AComponent, 'DataSource');
  Result.ListSource := PropValue(AComponent, 'ListSource');
  Result.ProviderName := PropValue(AComponent, 'ProviderName');
  Result.DataField := PropValue(AComponent, 'DataField');
  Result.ListField := PropValue(AComponent, 'ListField');
  Result.KeyField := PropValue(AComponent, 'KeyField');
end;

/// <summary>Formular-Editor des Moduls AName samt Formular; nil ohne.</summary>
function EditorOfModule(const AName: string; out ARoot: TComponent): IOTAFormEditor;
var
  mEditor: IOTAFormEditor;
begin
  for mEditor in OpenFormEditors do
  begin
    ARoot := TAtlasIdeDesignerView.RootOf(mEditor);
    if (ARoot <> nil) and SameText(ARoot.Name, AName) then
    begin
      Exit(mEditor);
    end;
  end;
  ARoot := nil;
  Result := nil;
end;

/// <summary>Leiste unter dem Designer: zuerst ganz unten einhängen, dann unten ausrichten.</summary>
procedure PlaceBar(ABar: TControl; AEditorParent: TWinControl);
begin
  if ABar.Parent = AEditorParent then
  begin
    Exit;
  end;
  ABar.Top := AEditorParent.ClientHeight;
  ABar.Align := alBottom;
  ABar.Parent := AEditorParent;
end;

{ TAtlasIdeDataBindings }

constructor TAtlasIdeDataBindings.Create;
begin
  inherited Create;
  FPalette := TAtlasPaletteImages.Create;
  FHost := TAtlasEditorBarHost.Create('Datenbindung', TAtlasFeature.DesignerBar,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateBar;
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      PlaceBar(ABar, AEditorParent);
    end);
  FHost.ShowIn := TAtlasEditorBarView.Designer;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTick;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeDataBindings.Destroy;
begin
  FTimer.Free;
  FHost.Free;
  FPalette.Free;
  inherited Destroy;
end;

function TAtlasIdeDataBindings.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
begin
  if not ASettings.DesignerDataBindings then
  begin
    Hide;
    Exit(Default(TAtlasDesignerButton));
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.DataBindings,
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.DbHint));
  Result.Pressed := FShown;
end;

procedure TAtlasIdeDataBindings.Toggle;
begin
  if FShown then
  begin
    Hide;
    Exit;
  end;
  FShown := True;
  FKey := '';
  FHost.Ensure;
  Refresh;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeDataBindings.Hide;
begin
  FShown := False;
  FTimer.Enabled := False;
  FKey := '';
  if FHost.Count > 0 then
  begin
    FHost.Clear;
  end;
end;

procedure TAtlasIdeDataBindings.ApplyTheme;
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasIdeStyle.BarColors;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasBindingBar(ABar).ApplyColors(mColors);
    end);
end;

function TAtlasIdeDataBindings.CreateBar: TAtlasBindingBar;
var
  mHost: TAtlasEditorBarHost;
  mPalette: TAtlasPaletteImages;
begin
  Result := TAtlasBindingBar.Create(nil);
  mHost := FHost;
  mPalette := FPalette;
  Result.ApplyColors(TAtlasIdeStyle.BarColors);
  Result.Images := FPalette.Images;
  Result.OnImage :=
    function(AClassName: string): Integer
    begin
      Result := mPalette.IndexOfName(AClassName);
    end;
  Result.OnSelect :=
    procedure(AId: string)
    begin
      Select(AId);
    end;
  Result.OnDisabled :=
    procedure(ASender: TObject)
    begin
      mHost.Disabled(ASender);
    end;
  // Neue Leiste: beim nächsten Takt füllen.
  FKey := '';
end;

procedure TAtlasIdeDataBindings.Tick(Sender: TObject);
begin
  if not FHost.Guard then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      FHost.Ensure;
      Refresh;
    end);
end;

function TAtlasIdeDataBindings.ObjectsOf(ARoot: TComponent): TArray<TAtlasBindingObject>;
var
  mIndex, mSet: Integer;
  mComponent, mDataSet: TComponent;
  mField: string;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    if (mComponent.Name <> '') and not IsField(mComponent, mDataSet, mField) then
    begin
      FPalette.Remember(mComponent.ClassType);
      Result := Result + [ObjectOf(mComponent, ARoot.Name)];
    end;
  end;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if not IsField(ARoot.Components[mIndex], mDataSet, mField) then
    begin
      Continue;
    end;
    for mSet := 0 to High(Result) do
    begin
      if SameText(Result[mSet].Name, mDataSet.Name) then
      begin
        Result[mSet].Fields := Result[mSet].Fields + [mField];
      end;
    end;
  end;
end;

procedure TAtlasIdeDataBindings.Refresh;
var
  mEditor, mOther: IOTAFormEditor;
  mRoot, mOtherRoot: TComponent;
  mSelected: TArray<TComponent>;
  mAll: TArray<TAtlasBindingObject>;
  mName, mKey: string;
  mTrail: TAtlasBindingTrail;
begin
  if not FShown or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mAll := ObjectsOf(mRoot);
  for mOther in OpenFormEditors do
  begin
    mOtherRoot := TAtlasIdeDesignerView.RootOf(mOther);
    if (mOtherRoot <> nil) and (mOtherRoot <> mRoot) then
    begin
      mAll := mAll + ObjectsOf(mOtherRoot);
    end;
  end;
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  mName := '';
  if Length(mSelected) = 1 then
  begin
    mName := mSelected[0].Name;
  end;
  mKey := mRoot.Name + cKeySeparator + mName + cKeySeparator + TAtlasDataBindings.Signature(mAll);
  if mKey = FKey then
  begin
    Exit;
  end;
  FKey := mKey;
  mTrail := TAtlasDataBindings.Trail(mAll, mRoot.Name, mName);
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasBindingBar(ABar).ShowTrail(mTrail, mName <> '');
    end);
end;

procedure TAtlasIdeDataBindings.Select(const AId: string);
var
  mEditor, mCurrent: IOTAFormEditor;
  mRoot, mComponent, mCurrentRoot: TComponent;
  mModule, mName: string;
  mDot: Integer;
begin
  mDot := Pos('.', AId);
  mModule := Copy(AId, 1, mDot - 1);
  mName := Copy(AId, mDot + 1, MaxInt);
  mEditor := EditorOfModule(mModule, mRoot);
  if mEditor = nil then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(mName);
  if mComponent = nil then
  begin
    Exit;
  end;
  // Anderes Modul (Datenmodul): erst seinen Designer zeigen, dann dort wählen.
  if not TAtlasDesignerAccess.Current(mCurrent, mCurrentRoot) or (mCurrentRoot <> mRoot) then
  begin
    mEditor.Show;
  end;
  TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mComponent]);
end;

end.
