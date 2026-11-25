unit Atlas.Core.Hover.IdeHelpInsight;

// Help Insight der IDE neben dem Atlas-Tooltip: Delphi 12 merkt sich den
// Schalter „Symbolbeschreibung“ für einen fremden Code-Insight-Manager nicht
// (nicht in der Registry, nach jedem Start wieder an), und die IDE öffnet ihr
// Fenster auch, wenn der Manager leeres HTML liefert. Atlas blendet das
// Fenster deshalb aus, sobald es erscheint. Hier steht nur die Entscheidung;
// Atlas.IDE.Hover.IdeHelpInsight beobachtet die Fenster.

interface

type
  TAtlasIdeHelpInsight = class
  public
    const
      /// <summary>Fensterklasse des Help-Insight-Fensters der IDE (Delphi 12 und 13).</summary>
      cWindowClass = 'THelpInsightWindowImpl';
    /// <summary>Ist AWindowClass das Help-Insight-Fenster der IDE?</summary>
    class function IsHelpInsightWindow(const AWindowClass: string): Boolean; static;
    /// <summary>Fenster der Klasse AWindowClass ausblenden? Nur das Help-Insight-Fenster, nur solange Atlas den
    /// Tooltip selbst zeigt (AOwnTooltip) und die Datei im Editor bedient (AHandlesFile); sonst gehört der
    /// Hinweis der IDE.</summary>
    class function ShouldHide(const AWindowClass: string; AOwnTooltip, AHandlesFile: Boolean): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasIdeHelpInsight }

class function TAtlasIdeHelpInsight.IsHelpInsightWindow(const AWindowClass: string): Boolean;
begin
  // Fensterklassen vergleicht Windows ohne Groß-/Kleinschreibung.
  Result := SameText(AWindowClass, cWindowClass);
end;

class function TAtlasIdeHelpInsight.ShouldHide(const AWindowClass: string; AOwnTooltip, AHandlesFile: Boolean):
  Boolean;
begin
  Result := AOwnTooltip and AHandlesFile and IsHelpInsightWindow(AWindowClass);
end;

end.
