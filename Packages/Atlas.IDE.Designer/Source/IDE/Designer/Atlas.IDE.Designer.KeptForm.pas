unit Atlas.IDE.Designer.KeptForm;

// Gemerkte Komponenten des aktiven Designers über einen modalen Dialog oder
// einen Zug mit der Maus hinweg (TAtlasKeptComponents), in der IDE: Take
// merkt Datei, Formular und Komponenten; Holds fragt den aktiven Designer
// neu und ist nur wahr, wenn dieselbe Datei mit demselben Formular offen ist
// und alle gemerkten Komponenten noch darin leben. Werkzeuge rufen Holds
// nach jedem modalen Dialog und vor jedem Schreiben während eines Zugs; bei
// False brechen sie ab (LostText in die Meldungen), statt auf gemerkte
// Verweise zuzugreifen. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Designer.KeptComponents;

type
  TAtlasDesignerKept = record
  private
    FFileName: string;
    FComponents: TAtlasKeptComponents;
  public
    /// <summary>Datei von AEditor und Formular ARoot merken.</summary>
    class function Take(const AEditor: IOTAFormEditor; ARoot: TComponent): TAtlasDesignerKept; static;
    procedure Add(AItem: TComponent); overload;
    procedure Add(const AItems: TArray<TComponent>); overload;
    procedure Add(const AItems: TArray<TControl>); overload;
    /// <summary>True, wenn der aktive Designer noch dieselbe Datei mit demselben Formular zeigt und alle
    /// gemerkten Komponenten darin leben.</summary>
    function Holds: Boolean;
    /// <summary>Wie Holds; bei False geht LostText an AOnMessage.</summary>
    function Reported(const AOnMessage: TProc<string>): Boolean;
    /// <summary>True, wenn AOther dieselbe Datei, dasselbe Formular und dieselben Komponenten merkt.</summary>
    function SameAs(const AOther: TAtlasDesignerKept): Boolean;
    /// <summary>Datei des Formulars beim Merken.</summary>
    function FileName: string;
    /// <summary>Meldung, wenn Holds False ist: Formular geändert, abgebrochen.</summary>
    class function LostText: string; static;
  end;

implementation

uses
  Atlas.UI.Designer.ToolStrings,
  Atlas.IDE.Designer.Access;

class function TAtlasDesignerKept.Take(const AEditor: IOTAFormEditor; ARoot: TComponent): TAtlasDesignerKept;
begin
  Result := Default(TAtlasDesignerKept);
  if AEditor <> nil then
  begin
    Result.FFileName := AEditor.FileName;
  end;
  Result.FComponents := TAtlasKeptComponents.Take(ARoot);
end;

procedure TAtlasDesignerKept.Add(AItem: TComponent);
begin
  FComponents.Add(AItem);
end;

procedure TAtlasDesignerKept.Add(const AItems: TArray<TComponent>);
var
  mItem: TComponent;
begin
  for mItem in AItems do
  begin
    FComponents.Add(mItem);
  end;
end;

procedure TAtlasDesignerKept.Add(const AItems: TArray<TControl>);
var
  mItem: TControl;
begin
  for mItem in AItems do
  begin
    FComponents.Add(mItem);
  end;
end;

function TAtlasDesignerKept.Holds: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (FFileName <> '') and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FFileName) and FComponents.Alive(mRoot);
end;

function TAtlasDesignerKept.Reported(const AOnMessage: TProc<string>): Boolean;
begin
  Result := Holds;
  if not Result and Assigned(AOnMessage) then
  begin
    AOnMessage(LostText);
  end;
end;

function TAtlasDesignerKept.SameAs(const AOther: TAtlasDesignerKept): Boolean;
begin
  Result := SameText(FFileName, AOther.FFileName) and FComponents.SameAs(AOther.FComponents);
end;

function TAtlasDesignerKept.FileName: string;
begin
  Result := FFileName;
end;

class function TAtlasDesignerKept.LostText: string;
begin
  Result := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.FormChanged);
end;

end.
