unit Atlas.IDE.Outline.NavigationHiding;

// Navigationsleiste der IDE („Typ suchen“/„Methode suchen“) ausblenden,
// solange die Brotkrumen an sind (editor.breadcrumbsHideIdeToolbar).
// Ausgeblendet wird über die Option der IDE (TAtlasIdeNavigationOption); nur
// wenn die IDE sie nicht hat, hängt TAtlasNavigationToolbar die Leiste je
// Editorfenster in ein eigenes Panel um (Netz). Beim Abbau kommt die Leiste
// zurück: Option zurück, wenn Atlas sie ausgeschaltet hatte, bzw.
// zurückgehängt. Abgetrennt vom Stand der Brotkrumen (TBreadcrumbsState).
// Nur im Hauptthread.

interface

uses
  Vcl.Controls,
  Atlas.UI.Outline.NavigationToolbar;

type
  TAtlasIdeNavigationHiding = class
  private
    FToolbars: TAtlasNavigationToolbar;
    /// <summary>Blendet die IDE die Navigationsleiste über ihre Option aus? Dann hängt Atlas nichts um.</summary>
    FByIde: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Nach den Einstellungen aus- bzw. wieder einblenden (Anlegen, Einstellungen geändert).</summary>
    procedure Apply;
    /// <summary>Netz für das Editorfenster AParent: Leiste umhängen, wenn die IDE keine Option hat.</summary>
    procedure ApplyTo(AParent: TWinControl);
    /// <summary>Navigationsleiste über die Option der IDE wieder zeigen (auch ohne angelegten Stand, z. B. wenn die
    /// IDE ohne Entladen endete).</summary>
    class procedure ShowAgain; static;
  end;

implementation

uses
  Atlas.IDE.Outline.NavigationOption,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeNavigationHiding }

constructor TAtlasIdeNavigationHiding.Create;
begin
  inherited Create;
  FToolbars := TAtlasNavigationToolbar.Create(nil);
end;

destructor TAtlasIdeNavigationHiding.Destroy;
begin
  ShowAgain;
  FToolbars.Free;
  inherited Destroy;
end;

procedure TAtlasIdeNavigationHiding.Apply;
var
  mHide: Boolean;
begin
  // Die Leiste blendet die IDE über ihre Option aus; umgehängt wird nur ohne diese Option (Netz).
  mHide := TAtlasIdeSettings.Current.BreadcrumbsHideIdeToolbar;
  FByIde := TAtlasIdeNavigationOption.Apply(mHide);
  if FByIde or not mHide then
  begin
    FToolbars.RestoreAll;
  end;
end;

class procedure TAtlasIdeNavigationHiding.ShowAgain;
begin
  TAtlasIdeNavigationOption.Apply(False);
end;

/// <summary>Netz, nur ohne Option der IDE (siehe Apply): Navigationsleiste in ein eigenes Panel umhängen.</summary>
procedure TAtlasIdeNavigationHiding.ApplyTo(AParent: TWinControl);
begin
  if FByIde then
  begin
    Exit;
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsHideIdeToolbar then
  begin
    FToolbars.Apply(AParent, True);
  end;
end;

end.
