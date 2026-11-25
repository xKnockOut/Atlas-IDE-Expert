unit Atlas.Core.Hover.IdeHelpInsight;

// Help Insight der IDE neben dem Atlas-Tooltip: Delphi 12 merkt sich den
// Schalter „Symbolbeschreibung“ für einen fremden Code-Insight-Manager nicht
// (nicht in der Registry, nach jedem Start wieder an), und die IDE öffnet ihr
// Fenster auch, wenn der Manager leeres HTML liefert. Atlas blendet das
// Fenster deshalb aus, sobald es erscheint. Hier steht nur die Entscheidung;
// Atlas.IDE.Hover.IdeHelpInsight beobachtet die Fenster.
// - Welche Datei zählt: die im Editor unter der Maus (Help Insight erscheint
//   beim Zeigen); ist keine bekannt, die im obersten Editor.
// - Der Wächter hängt am internen Klassennamen. Hat er in einer Sitzung, in
//   der Atlas den Tooltip zeigte, nie ein solches Fenster gesehen, steht das
//   im Protokoll: Dann hat die IDE die Klasse umbenannt oder Help Insight ist
//   aus.
// - Delphi 13: Ob die IDE die Schalter dort behält und der Umweg entfallen
//   kann, ist nicht geprüft; er gilt für beide Fassungen.

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
    /// <summary>Datei, nach der entschieden wird: AMouseFile (Editor unter der Maus), ohne sie ATopFile.</summary>
    class function FileToDecide(const AMouseFile, ATopFile: string): string; static;
    /// <summary>Protokollzeile beim Abbau, dass das Fenster nie erschien? Nur, wenn der Haken lief
    /// (AHooked), Atlas den Tooltip in einem Editor zeigte (AHovered) und das Fenster nie kam (not ASeen).</summary>
    class function ReportUnseen(AHooked, AHovered, ASeen: Boolean): Boolean; static;
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

class function TAtlasIdeHelpInsight.FileToDecide(const AMouseFile, ATopFile: string): string;
begin
  Result := AMouseFile;
  if Result = '' then
  begin
    Result := ATopFile;
  end;
end;

class function TAtlasIdeHelpInsight.ReportUnseen(AHooked, AHovered, ASeen: Boolean): Boolean;
begin
  Result := AHooked and AHovered and not ASeen;
end;

end.
