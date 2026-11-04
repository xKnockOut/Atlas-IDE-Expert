unit Atlas.UI.Welcome.TestSupport;

// Gemeinsame Hilfen der Willkommens-Tests (Atlas.UI.Welcome.*.Tests).

interface

uses
  System.Classes,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Frame;

type
  /// <summary>Bereich ohne Inhalt, der seine Aktualisierungen zählt.</summary>
  TTestSection = class(TAtlasWelcomeSectionFrame)
  public
    Updates: Integer;
    procedure UpdateContent; override;
  end;

/// <summary>Meldet für jede Kennung einen TTestSection-Bereich an.</summary>
procedure RegisterViews(const AIds: array of string);

/// <summary>Bereich mit Titel „Titel &lt;Kennung&gt;“ an Reihenfolge und Spalte.</summary>
function Section(const AId: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;

implementation

procedure TTestSection.UpdateContent;
begin
  Inc(Updates);
  inherited;
end;

procedure RegisterViews(const AIds: array of string);
var
  Id: string;
begin
  for Id in AIds do
  begin
    TAtlasWelcomeViews.Register(Id,
      function(AOwner: TComponent): TAtlasWelcomeSectionFrame
      begin
        Result := TTestSection.Create(AOwner);
      end);
  end;
end;

function Section(const AId: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(AId, 'Titel ' + AId, AOrder, AColumn, nil);
end;

end.
