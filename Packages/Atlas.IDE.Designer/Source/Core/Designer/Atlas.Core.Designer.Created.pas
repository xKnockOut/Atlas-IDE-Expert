unit Atlas.Core.Designer.Created;

// Komponenten, die ein Designer-Werkzeug angelegt hat, für sein
// „… rückgängig“ („Label erzeugen“, „In Reihe duplizieren“, „Einpacken in“),
// ohne VCL und Open Tools API über IAtlasDesignSurface.
// Zwischen Anlegen und Rückgängig geschieht im Designer viel: Der Benutzer
// löscht eine Kopie oder benennt sie um, legt eine neue unter dem frei
// gewordenen Namen an, wechselt das Formular oder schließt es und öffnet es
// wieder. Gemerkt wird deshalb die Komponente selbst, nicht ihr Name: Über
// FreeNotification fällt sie aus der Liste, sobald sie freigegeben wird,
// auch zusammen mit ihrem Container oder Formular. Rückgängig löscht die
// übrigen über den Designer (samt Feld in der Klasse) unter ihrem jetzigen
// Namen, rückwärts, damit Kinder vor ihren Containern gehen.
// Nur im Hauptthread.

interface

uses
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Designer.Surface;

type
  TAtlasDesignerCreated = class(TComponent)
  private
    FItems: TList<TComponent>;
  protected
    procedure Notification(AComponent: TComponent; AOperation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>AComponent merken (nil wird übergangen); sie fällt heraus, sobald sie freigegeben wird.</summary>
    procedure Add(AComponent: TComponent);
    /// <summary>Alles vergessen, ohne etwas zu löschen (neuer Lauf des Werkzeugs).</summary>
    procedure Clear;
    /// <summary>Gemerkte Komponenten, die noch leben.</summary>
    function Count: Integer;
    /// <summary>Lebt noch eine gemerkte Komponente im Formular von ASurface?</summary>
    function Holds(const ASurface: IAtlasDesignSurface): Boolean;
    /// <summary>Gemerkte Komponenten im Formular von ASurface rückwärts über den Designer löschen; danach ist die
    /// Liste leer. Ergebnis: Zahl der gelöschten. Ohne gemerkte Komponente in diesem Formular bleibt alles,
    /// wie es ist (anderes Formular aktiv).</summary>
    function Undo(const ASurface: IAtlasDesignSurface): Integer;
    /// <summary>Schlüssel von AComponent unter ARoot für IAtlasDesignSurface.DeleteComponent („Button1“, in Frames
    /// „Frame1.Button1“); '', wenn sie nicht über die Owner an ARoot hängt oder ein Name fehlt.</summary>
    class function KeyOf(ARoot, AComponent: TComponent): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasDesignerCreated }

constructor TAtlasDesignerCreated.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TList<TComponent>.Create;
end;

destructor TAtlasDesignerCreated.Destroy;
begin
  Clear;
  FItems.Free;
  inherited Destroy;
end;

procedure TAtlasDesignerCreated.Notification(AComponent: TComponent; AOperation: TOperation);
begin
  inherited Notification(AComponent, AOperation);
  if (AOperation = opRemove) and (FItems <> nil) then
  begin
    FItems.Remove(AComponent);
  end;
end;

procedure TAtlasDesignerCreated.Add(AComponent: TComponent);
begin
  if (AComponent = nil) or FItems.Contains(AComponent) then
  begin
    Exit;
  end;
  FItems.Add(AComponent);
  AComponent.FreeNotification(Self);
end;

procedure TAtlasDesignerCreated.Clear;
var
  mItem: TComponent;
begin
  for mItem in FItems.ToArray do
  begin
    mItem.RemoveFreeNotification(Self);
  end;
  FItems.Clear;
end;

function TAtlasDesignerCreated.Count: Integer;
begin
  Result := FItems.Count;
end;

class function TAtlasDesignerCreated.KeyOf(ARoot, AComponent: TComponent): string;
var
  mPart: TComponent;
begin
  Result := '';
  if (ARoot = nil) or (AComponent = nil) or (AComponent = ARoot) then
  begin
    Exit;
  end;
  mPart := AComponent;
  while (mPart <> nil) and (mPart <> ARoot) do
  begin
    if mPart.Name = '' then
    begin
      Exit('');
    end;
    Result := mPart.Name + '.' + Result;
    mPart := mPart.Owner;
  end;
  if mPart = nil then
  begin
    Exit('');
  end;
  Result := Result.Substring(0, Result.Length - 1);
end;

function TAtlasDesignerCreated.Holds(const ASurface: IAtlasDesignSurface): Boolean;
var
  mItem: TComponent;
begin
  Result := False;
  if (ASurface = nil) or (ASurface.Root = nil) then
  begin
    Exit;
  end;
  for mItem in FItems do
  begin
    if KeyOf(ASurface.Root, mItem) <> '' then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasDesignerCreated.Undo(const ASurface: IAtlasDesignSurface): Integer;
var
  mItems: TArray<TComponent>;
  mIndex: Integer;
  mKey: string;
begin
  Result := 0;
  if not Holds(ASurface) then
  begin
    Exit;
  end;
  mItems := FItems.ToArray;
  for mIndex := High(mItems) downto 0 do
  begin
    // Mit einem Container gelöschte Kinder sind schon aus der Liste gefallen.
    if FItems.Contains(mItems[mIndex]) then
    begin
      mKey := KeyOf(ASurface.Root, mItems[mIndex]);
      if (mKey <> '') and ASurface.DeleteComponent(mKey) then
      begin
        Inc(Result);
      end;
    end;
  end;
  Clear;
end;

end.
