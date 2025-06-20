FROM nialljb/freesurfer7.4.1-ants2.4-fsl AS base

############################

# shell settings
WORKDIR /freesurfer

# configure flywheel
ENV HOME=/root/
ENV FLYWHEEL="/flywheel/v0"
ENV PYTHONPATH="/flywheel/v0:$PYTHONPATH"

WORKDIR $FLYWHEEL
RUN mkdir -p $FLYWHEEL/input
RUN mkdir -p $FLYWHEEL/work
# Installing the current project
COPY ./ $FLYWHEEL/

RUN pip3 install flywheel-gear-toolkit && \
    pip3 install --upgrade flywheel-sdk


# Configure entrypoint
RUN bash -c 'chmod +wrx $FLYWHEEL/run.py' && \
    bash -c 'chmod +wrx $FLYWHEEL/app/*' && \
    bash -c 'chmod +wrx $FLYWHEEL/utils/*'
    
    
ENTRYPOINT ["python3","/flywheel/v0/run.py"] 
# Flywheel reads the config command over this entrypoint