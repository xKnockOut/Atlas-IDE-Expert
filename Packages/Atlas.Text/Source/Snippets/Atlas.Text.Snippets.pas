unit Atlas.Text.Snippets;

// Snippet-Text des LSP (gemeinsam für Server und Plugin): Zeichen maskieren, die in einem Snippet eine
// Bedeutung haben ("\", "$", "}"), damit fester Text neben Platzhaltern wie ${1:Name} unverändert bleibt.

interface

type
  TTextSnippets = class
  public
    /// <summary>AText mit "\" vor jedem "\", "$" und "}" ("a$b}c\" → "a\$b\}c\\").</summary>
    class function Escape(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils;

class function TTextSnippets.Escape(const AText: string): string;
begin
  Result := AText.Replace('\', '\\').Replace('$', '\$').Replace('}', '\}');
end;

end.
