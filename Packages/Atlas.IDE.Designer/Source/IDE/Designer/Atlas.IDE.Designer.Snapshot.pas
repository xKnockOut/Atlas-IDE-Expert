unit Atlas.IDE.Designer.Snapshot;

// Stand von Lage und Größe im Designer für „… rückgängig“ der Befehle im Menü
// „Anordnen“, die nur Lage und Größe ändern (#740, #742): Datei, alle
// Steuerelemente des Formulars mit BoundsRect und der Client des Formulars.
// Zurück geht es nur im selben Formular. Nur im Hauptthread.

interface

uses
  System.Classes,
  System.Types;

type
  TAtlasDesignerSnapshot = class
  private
    FFileName: string;
    FNames: TArray<string>;
    FBounds: TArray<TRect>;
    FRootClient: TPoint;
  public
    /// <summary>Stand von ARoot (Formular in AFileName) merken.</summary>
    procedure Take(const AFileName: string; ARoot: TComponent);
    /// <summary>Gibt es einen Stand für das Formular im aktiven Designer?</summary>
    function CanRestore: Boolean;
    /// <summary>Stand im aktiven Designer wiederherstellen; False ohne passenden Stand.</summary>
    function Restore: Boolean;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  ToolsAPI,
  Atlas.IDE.Designer.Access;

procedure TAtlasDesignerSnapshot.Take(const AFileName: string; ARoot: TComponent);
var
  mIndex: Integer;
begin
  FFileName := AFileName;
  FNames := nil;
  FBounds := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if ARoot.Components[mIndex] is TControl then
    begin
      FNames := FNames + [ARoot.Components[mIndex].Name];
      FBounds := FBounds + [TControl(ARoot.Components[mIndex]).BoundsRect];
    end;
  end;
  FRootClient := Point(0, 0);
  if ARoot is TControl then
  begin
    FRootClient := Point(TControl(ARoot).ClientWidth, TControl(ARoot).ClientHeight);
  end;
end;

function TAtlasDesignerSnapshot.CanRestore: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (FFileName <> '') and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FFileName);
end;

function TAtlasDesignerSnapshot.Restore: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mIndex, mPass: Integer;
begin
  Result := CanRestore and TAtlasDesignerAccess.Current(mEditor, mRoot);
  if not Result then
  begin
    Exit;
  end;
  if (mRoot is TControl) and (FRootClient.X > 0) then
  begin
    TControl(mRoot).ClientWidth := FRootClient.X;
    TControl(mRoot).ClientHeight := FRootClient.Y;
  end;
  // Zweimal: Ein Parent, der nach seinen Kindern zurückgesetzt wird, zieht verankerte Kinder noch einmal mit.
  for mPass := 1 to 2 do
  begin
    for mIndex := 0 to High(FNames) do
    begin
      mComponent := mRoot.FindComponent(FNames[mIndex]);
      if (mComponent is TControl) and (TControl(mComponent).BoundsRect <> FBounds[mIndex]) then
      begin
        TControl(mComponent).BoundsRect := FBounds[mIndex];
      end;
    end;
  end;
  FFileName := '';
  FNames := nil;
  FBounds := nil;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
end;

end.
