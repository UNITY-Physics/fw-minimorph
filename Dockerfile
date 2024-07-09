FROM nialljb/freesurfer7.4.1-ants2.4-fsl as base

############################

# shell settings
WORKDIR /freesurfer

# configure flywheel
ENV HOME=/root/
ENV FLYWHEEL="/flywheel/v0"
WORKDIR $FLYWHEEL
RUN mkdir -p $FLYWHEEL/input
RUN mkdir -p $FLYWHEEL/work
# Installing the current project
COPY ./ $FLYWHEEL/

RUN pip install flywheel-gear-toolkit && \
    pip install flywheel-sdk

# Configure entrypoint
RUN bash -c 'chmod +rx $FLYWHEEL/run.py' && \
    bash -c 'chmod +rx $FLYWHEEL/app/' 
    
ENTRYPOINT ["python3","/flywheel/v0/main.sh"] 
# Flywheel reads the config command over this entrypoint