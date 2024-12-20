/**
 * Attach event listeners to elements and handle click events.
 *
 * @description This code attaches click event listeners to the `githubLink` and `headerSource` elements.
 * It prevents the default behavior of the click event and opens specific URLs in new tabs when the elements are clicked.
 * The `githubLink` element opens the GitHub repository URL,
 * while the `headerSource` element opens the CNAG website URL.
 *
 * @param {Object} event - The click event object.
 */

window.addEventListener('load', () => {
  const headerSource = document.querySelector('.md-header__source');
  const githubLink = document.querySelector('.md-source__repository.md-source__repository--active');

  githubLink.addEventListener('click', (event) => {
    event.preventDefault();
    window.open(
      "https://github.com/CNAG-Biomedical-Informatics/convert-pheno",
      '_blank'
    );
  });
  headerSource.addEventListener('click', (event) => {
    event.preventDefault();

    // if clicked on any child element of githubLink do nothing
    if (event.target !== githubLink && !githubLink.contains(event.target)) {
      window.open(
        "https://www.cnag.eu",
        '_blank'
      );
    }
  });
});
