FROM mambaorg/micromamba:1.5.10

SHELL ["/bin/bash", "-lc"]

RUN micromamba install -y -n base \
      -c conda-forge -c bioconda \
      python=3.10 "numpy<1.24" telescope samtools pip \
    && micromamba clean -a -y

USER root

COPY telescope_wrapper.sh /usr/local/bin/telescope
COPY samtools_wrapper.sh /usr/local/bin/samtools

RUN chmod +x /usr/local/bin/telescope /usr/local/bin/samtools

RUN /opt/conda/bin/python -c "import pathlib, telescope; root=pathlib.Path(telescope.__file__).resolve().parent; p=root/'utils'/'model.py'; txt=p.read_text(); p.write_text(txt.replace('np.int','int')); print('patched', p)"

RUN /opt/conda/bin/python -c "import numpy as np, telescope, telescope.__main__; print('numpy', np.version); print('telescope module OK')" \
    && /usr/local/bin/telescope --help >/tmp/telescope_help.txt \
    && grep -E "assign|usage|Usage" /tmp/telescope_help.txt >/dev/null \
    && /usr/local/bin/telescope assign -h >/tmp/telescope_assign_help.txt \
    && grep -E "samfile|gtffile|attribute" /tmp/telescope_assign_help.txt >/dev/null \
    && /usr/local/bin/samtools --version | head -n 1

USER $MAMBA_USER

WORKDIR /project

CMD ["bash"]
